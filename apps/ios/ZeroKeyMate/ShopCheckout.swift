import Foundation
import Combine
import MateCore
import MateAgeProof

/// Durable context contains no card data. The limited payment authorization,
/// when present, stays in the device-only Keychain for exact-authorization retry.
private struct SavedShopOrder: Codable {
    let connection: AgeShopConnection
    let key: String
    var order: AgeShopOrder
    var paymentHeader: String?
    var paymentExpiresAt: UInt64?
    var paymentRetiredAtBlockHash: String?
    var completed = false
}
private struct PendingShopCreation: Codable {
    let connection: AgeShopConnection
    let key: String
    let payer: String
}

@MainActor final class ShopCheckout: ObservableObject {
    enum Phase: Equatable { case initial, checking, review, card, readingCard, proving, verifying, paymentApproval, paying, pending, complete, expired, unavailable }
    @Published private(set) var phase = Phase.initial
    @Published private(set) var order: AgeShopOrder?
    @Published private(set) var message: String?
    @Published private(set) var storeURL: URL?
    @Published private(set) var canStart = false
    let reader = MyNumberNFCService()
    private let prover = AgeProofService()
    private let storageKey = "base-sepolia-age-shop-order-v1"
    private let creationKey = "base-sepolia-age-shop-creation-v1"
    private var client: AgeShopClient?
    private var connection: AgeShopConnection?
    private var saved: SavedShopOrder?
    @Published private var operation: Task<Void, Never>?
    private var generation = UUID()
    var busy: Bool { operation != nil }
    static func hasSavedOrder() -> Bool {
        (try? LocalSecrets.read(SavedShopOrder.self, key: "base-sepolia-age-shop-order-v1")) != nil ||
        (try? LocalSecrets.read(PendingShopCreation.self, key: "base-sepolia-age-shop-creation-v1")) != nil
    }

    func load() {
        guard phase == .initial else { return }
        phase = .checking
        run { ticket in
            if let stored = try LocalSecrets.read(SavedShopOrder.self, key: self.storageKey) {
                _ = try stored.connection.validate()
                self.connection = stored.connection; self.saved = stored; self.order = stored.order
                self.storeURL = URL(string: stored.connection.origin)
                self.client = try AgeShopClient(connection: stored.connection)
                try self.check(ticket)
                // A saved success is rechecked against both providers before
                // being presented as success after a restart.
                try await self.recover(ticket)
                return
            }
            if let pending = try LocalSecrets.read(PendingShopCreation.self, key: self.creationKey) {
                self.storeURL = try pending.connection.validate(); self.connection = pending.connection
                self.client = try AgeShopClient(connection: pending.connection)
                try await self.create(pending, ticket: ticket)
                return
            }
            guard let url = Bundle.main.url(forResource: "ShopConnection", withExtension: "json") else {
                self.phase = .unavailable; self.message = "The store connection is not installed yet. No order or payment has been made."; return
            }
            let connection = try JSONDecoder().decode(AgeShopConnection.self, from: Data(contentsOf: url))
            self.storeURL = try connection.validate(); self.connection = connection
            let client = try AgeShopClient(connection: connection); self.client = client
            try await self.prover.prepare()
            guard try await client.ready() else { throw ProductError.unavailable("The store cannot accept new orders right now. Nothing was paid.") }
            try self.check(ticket); self.canStart = true; self.phase = .review
        }
    }

    func startOrder(wallet: WalletService) {
        guard !busy, phase == .review, order == nil, canStart, client != nil, let connection else { return }
        guard let payer = wallet.ownerAddress else { message = "Connect your wallet first. No order has been sent."; return }
        phase = .checking; message = nil
        run { ticket in
            let key = String(CanonicalBytes.hexString(try LocalSecrets.random32()).dropFirst(2))
            let pending = PendingShopCreation(connection: connection, key: key, payer: payer)
            // Even a lost creation response must resume the same capability.
            try LocalSecrets.write(pending, key: self.creationKey)
            try await self.create(pending, ticket: ticket)
        }
    }
    private func create(_ pending: PendingShopCreation, ticket: UUID) async throws {
        guard let client else { throw ProductError.invalidResponse }
        let order = try await client.create(payer: pending.payer, key: pending.key)
        try check(ticket)
        let saved = SavedShopOrder(connection: pending.connection, key: pending.key, order: order)
        try LocalSecrets.write(saved, key: storageKey)
        self.saved = saved; self.order = order
        try LocalSecrets.delete(creationKey)
        phase = recoverablePhase
    }

    func readCard(pin: String, wallet: WalletService) {
        guard !busy, phase == .card, let saved, let client, JPKICardReader.validSigningPIN(pin) else { return }
        message = nil
        phase = .readingCard
        run { ticket in
            let order = saved.order
            let challenge = try JPKIChallenge(orderHash: CanonicalBytes.hex(order.orderHash, count: 32),
                                               nonce: CanonicalBytes.hex(order.paymentNonce, count: 32))
            let credential = try await self.reader.authenticate(pin: pin, challenge: challenge)
            try self.check(ticket); self.phase = .proving
            let proof = try await self.prover.prove(authentication: credential.authentication,
                orderHash: CanonicalBytes.hex(order.orderHash, count: 32), nonce: CanonicalBytes.hex(order.paymentNonce, count: 32),
                referenceTime: order.createdAt, expiresAt: order.expiresAt)
            try self.check(ticket); self.phase = .verifying
            let verified = try await client.verifyAge(order: order, key: saved.key, proof: proof)
            try self.check(ticket); try self.store(verified)
            self.phase = .paymentApproval
            try await self.signAndPay(wallet: wallet, ticket: ticket)
        }
    }

    func continuePayment(wallet: WalletService) {
        guard !busy, phase == .paymentApproval else { return }
        run { ticket in try await self.signAndPay(wallet: wallet, ticket: ticket) }
    }

    private func signAndPay(wallet: WalletService, ticket: UUID) async throws {
        guard let client, let saved, saved.paymentHeader == nil, saved.paymentRetiredAtBlockHash == nil,
              saved.order.state == .ageVerified else { throw ProductError.invalidResponse }
        let required = try await client.paymentChallenge(order: saved.order, key: saved.key)
        try check(ticket)
        let signature = try await wallet.signShopPayment(order: saved.order, required: required) {
            try self.check(ticket)
            guard self.saved?.order.orderHash == saved.order.orderHash, self.saved?.paymentHeader == nil,
                  saved.order.expiresAt > UInt64(Date().timeIntervalSince1970) else { throw AgeShopError.expiredOrder }
        }
        try check(ticket)
        var pending = saved; pending.paymentHeader = signature.header; pending.paymentExpiresAt = signature.validBefore
        // Save the exact limited authorization BEFORE it can be broadcast.
        // A timeout or restart cannot manufacture a second nonce/signature.
        try LocalSecrets.write(pending, key: storageKey); self.saved = pending; phase = .paying
        do {
            let result = try await client.pay(order: pending.order, key: pending.key, header: signature.header)
            try check(ticket); try store(result)
        } catch {
            try check(ticket); phase = .pending
            message = "The payment result is not confirmed yet. Check this same order; do not create another payment."
            return
        }
        try await recover(ticket)
    }

    func checkOrder() { guard saved != nil, !busy else { return }; phase = .checking; run { try await self.recover($0) } }
    private func recover(_ ticket: UUID) async throws {
        guard let client, let saved else { throw ProductError.invalidResponse }
        let current = try await client.status(order: saved.order, key: saved.key)
        try check(ticket); try store(current)
        if current.state == .complete {
            phase = .pending
            async let base = EthereumRPC(url: "https://sepolia.base.org", chainID: AgeShopProtocol.chainID).confirmShop(current)
            async let independent = EthereumRPC(url: "https://base-sepolia-rpc.publicnode.com", chainID: AgeShopProtocol.chainID).confirmShop(current)
            let hashes = try await (base, independent)
            try check(ticket); guard hashes.0 == hashes.1 else { throw ProductError.invalidResponse }
            var complete = self.saved!; complete.paymentHeader = nil; complete.paymentExpiresAt = nil; complete.completed = true
            try LocalSecrets.write(complete, key: storageKey); self.saved = complete
            phase = .complete; message = nil
        } else if current.state == .paymentExpired || (saved.paymentExpiresAt.map { $0 <= UInt64(Date().timeIntervalSince1970) } ?? false) {
            phase = .pending
            // Compare against the expiration we saved BEFORE sending the actual
            // signature. A shop must not invent an earlier deadline to close it.
            // A lost POST can leave the shop at age_verified with no deadline.
            // Our saved signed deadline still permits a read-only unused check.
            guard let end = saved.paymentExpiresAt,
                  current.paymentValidBefore == nil || end == current.paymentValidBefore else { throw AgeShopError.invalidPayment }
            let base = EthereumRPC(url: "https://sepolia.base.org", chainID: AgeShopProtocol.chainID)
            let independent = EthereumRPC(url: "https://base-sepolia-rpc.publicnode.com", chainID: AgeShopProtocol.chainID)
            async let firstHeight = base.finalizedShopHeight()
            async let secondHeight = independent.finalizedShopHeight()
            let heights = try await (firstHeight, secondHeight)
            let height = min(heights.0, heights.1)
            async let first = base.confirmUnusedShop(current, validBefore: end, blockNumber: height)
            async let second = independent.confirmUnusedShop(current, validBefore: end, blockNumber: height)
            let hashes = try await (first, second)
            try check(ticket); guard hashes.0 == hashes.1 else { throw ProductError.invalidResponse }
            var closed = self.saved!; closed.paymentHeader = nil; closed.paymentRetiredAtBlockHash = hashes.0
            try LocalSecrets.write(closed, key: storageKey); self.saved = closed
            phase = .expired; message = nil
        } else if saved.paymentHeader != nil || current.state == .paymentPending {
            phase = .pending
            message = "Checking the original payment. Its order and nonce are preserved."
        } else if current.expiresAt <= UInt64(Date().timeIntervalSince1970) {
            phase = .unavailable; message = "This order expired before payment. Nothing was paid."
        } else if current.state == .ageVerified { phase = .paymentApproval }
        else { phase = .card }
    }

    func retryOriginalPayment() {
        guard !busy, phase == .pending, let saved, let header = saved.paymentHeader,
              let expires = saved.paymentExpiresAt, expires > UInt64(Date().timeIntervalSince1970), let client else { return }
        phase = .paying; message = nil
        run { ticket in
            let next = try await client.pay(order: saved.order, key: saved.key, header: header)
            try self.check(ticket); try self.store(next); try await self.recover(ticket)
        }
    }
    var canRetryOriginal: Bool {
        phase == .pending && saved?.paymentHeader != nil && (saved?.paymentExpiresAt ?? 0) > UInt64(Date().timeIntervalSince1970)
    }
    private func store(_ order: AgeShopOrder) throws {
        guard var saved, saved.order.orderHash == order.orderHash else { throw AgeShopError.invalidOrder }
        saved.order = order; try LocalSecrets.write(saved, key: storageKey)
        self.saved = saved; self.order = order
    }
    private func run(_ body: @escaping @MainActor (UUID) async throws -> Void) {
        guard operation == nil else { return }
        let ticket = UUID(); generation = ticket
        operation = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == ticket { self.operation = nil } }
            do { try await body(ticket) }
            catch is CancellationError { }
            catch {
                guard self.generation == ticket else { return }
                self.message = Self.explanation(error)
                self.phase = self.recoverablePhase
            }
        }
    }
    private func check(_ ticket: UUID) throws {
        try Task.checkCancellation(); guard generation == ticket else { throw CancellationError() }
    }
    func cancel() {
        generation = UUID(); operation?.cancel(); operation = nil; reader.cancel()
        // Saved payment state intentionally survives closing/backgrounding.
        // Foregrounding may check status, but must never resume PIN use or sign.
        phase = .initial; canStart = false
    }
    private var recoverablePhase: Phase {
        guard let saved else { return .unavailable }
        if saved.paymentRetiredAtBlockHash != nil { return .pending }
        if saved.paymentHeader != nil || [.paymentPending, .paymentExpired, .complete].contains(saved.order.state) { return .pending }
        if saved.order.expiresAt <= UInt64(Date().timeIntervalSince1970) { return .unavailable }
        return saved.order.state == .ageVerified ? .paymentApproval : .card
    }
    func retryAvailability() {
        guard !busy else { return }
        message = nil; phase = .initial; load()
    }
    var canStartNew: Bool {
        phase == .complete || phase == .expired || (phase == .unavailable && saved?.paymentHeader == nil && (saved?.order.expiresAt ?? .max) <= UInt64(Date().timeIntervalSince1970))
    }
    func startNew() {
        guard canStartNew else { return }
        do {
            if let saved, saved.completed {
                var history = try LocalSecrets.read([SavedShopOrder].self, key: "base-sepolia-shop-history") ?? []
                history.append(saved); try LocalSecrets.write(Array(history.suffix(20)), key: "base-sepolia-shop-history")
            }
            try LocalSecrets.delete(storageKey)
            try LocalSecrets.delete(creationKey)
            saved = nil; order = nil; message = nil; phase = .initial; load()
        } catch { message = Self.explanation(error) }
    }
    static func explanation(_ error: Error) -> String {
        if let card = error as? MyNumberCardError {
            switch card {
            case .pinRejected(let attempts): return "The signature PIN was rejected. \(attempts) attempts remain. Mate did not retry."
            case .pinBlocked: return "The card PIN is locked. Mate made no further attempt."
            default: return "The card could not be read. No personal information was sent."
            }
        }
        if error is JPKIVerificationError || error is JPKIAgeWitnessError {
            return "This card could not be authenticated for this order on the phone. No card information was sent."
        }
        if let error = error as? CardScanError {
            if error == .unavailable { return "Physical card scanning is not available on this device." }
            return "The card scan did not finish. Enter the signature PIN again only when you want to retry."
        }
        if error is AgeShopError { return "The order or payment details could not be verified. No new payment was authorized." }
        if let error = error as? ProductError { return error.localizedDescription }
        return "This step could not be completed. Your existing order was kept; no replacement payment was created."
    }
}
