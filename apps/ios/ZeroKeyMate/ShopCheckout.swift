import Foundation
import Combine
import MateCore
import MateAgeProof

/// Durable context contains no card data. The limited payment authorization,
/// when present, stays in the device-only Keychain for exact-authorization retry.
struct SavedShopOrder: Codable {
    let connection: AgeShopConnection
    let key: String
    var order: AgeShopOrder
    var paymentHeader: String?
    var paymentExpiresAt: UInt64?
    var paymentRetiredAtBlockHash: String?
    var locallyProvenOrderHash: String?
    var proofTiming: AgeProofTiming?
    var ageProofFailure: AgeProofFailure?
    var pendingAgeProof: VerifiedAgeProof?
    var completed = false
}
private struct PendingShopCreation: Codable {
    let connection: AgeShopConnection
    let key: String
    let payer: String
}
struct ShopPurchaseRecord: Identifiable, Sendable {
    let id: String
    let date: Date
    let transaction: String
}

@MainActor final class ShopCheckout: ObservableObject {
    enum Phase: Equatable { case initial, checking, review, funding, card, preparingCard, readingCard, proving, proofFailed, verifying, verificationFailed, paymentApproval, paying, pending, complete, expired, unavailable }
    @Published private(set) var phase = Phase.initial
    @Published private(set) var order: AgeShopOrder?
    @Published private(set) var message: String?
    @Published private(set) var storeURL: URL?
    @Published private(set) var canStart = false
    @Published private(set) var fundingAddress: String?
    @Published private(set) var proofStartedAt: ContinuousClock.Instant?
    var proofTiming: AgeProofTiming? {
        guard let saved, Self.hasLocalProof(saved.order, marker: saved.locallyProvenOrderHash) else { return nil }
        return saved.proofTiming
    }
    let reader = MyNumberNFCService()
    private let prover = AgeProofService()
    private let storageKey = "arc-testnet-age-shop-order-v1"
    private let creationKey = "arc-testnet-age-shop-creation-v1"
    private var client: AgeShopClient?
    private var connection: AgeShopConnection?
    private var saved: SavedShopOrder?
    // One order only, RAM only. Never keep the password. Closing/backgrounding,
    // expiry and successful proof creation release the authenticated credential.
    private var ageAuthentication: (hash: String, value: UnverifiedJPKIAuthentication)?
    private var ageSubmission: (hash: String, value: MeasuredAgeProof)?
    private var ageExpiry: Task<Void, Never>?
    var proofFailureCode: String? { saved?.ageProofFailure?.rawValue }
    @Published private var operation: Task<Void, Never>?
    private var generation = UUID()
    var busy: Bool { operation != nil }
    static func hasSavedOrder() -> Bool {
        (try? LocalSecrets.read(SavedShopOrder.self, key: "arc-testnet-age-shop-order-v1")) != nil ||
        (try? LocalSecrets.read(PendingShopCreation.self, key: "arc-testnet-age-shop-creation-v1")) != nil
    }
    /// The spoken answer uses the same validated recovery as the purchase UI.
    /// This path can only read/check an existing order. It cannot scan, create an
    /// order, submit a proof, ask a wallet to sign, or broadcast a payment.
    static func savedOrderAnswer() async -> String {
        let checkout = ShopCheckout()
        defer { checkout.cancel() }
        do {
            guard let stored = try LocalSecrets.read(SavedShopOrder.self, key: checkout.storageKey) else {
                return "I cannot confirm a completed purchase. Please check the saved order."
            }
            _ = try stored.connection.validate()
            checkout.saved = stored; checkout.order = stored.order
            checkout.client = try AgeShopClient(connection: stored.connection)
            try await checkout.recover(checkout.generation)
            return checkout.phase.purchaseAnswer
        } catch {
            return "I couldn't check the saved order right now. I cannot confirm that the purchase is complete."
        }
    }
    static func completedPurchases() throws -> [ShopPurchaseRecord] {
        var records = try LocalSecrets.read([SavedShopOrder].self, key: "arc-testnet-shop-history") ?? []
        if let current = try LocalSecrets.read(SavedShopOrder.self, key: "arc-testnet-age-shop-order-v1") { records.append(current) }
        var seen = Set<String>()
        return records.reversed().compactMap { saved in
            guard saved.completed, saved.order.state == .complete, seen.insert(saved.order.id).inserted,
                  let transaction = saved.order.paymentTransaction,
                  (try? CanonicalBytes.hex(transaction, count: 32)) != nil else { return nil }
            return ShopPurchaseRecord(id: saved.order.id, date: Date(timeIntervalSince1970: Double(saved.order.createdAt)), transaction: transaction)
        }
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
                if let proof = stored.pendingAgeProof, let timing = stored.proofTiming,
                   Self.hasLocalProof(stored.order, marker: stored.locallyProvenOrderHash),
                   stored.order.expiresAt > UInt64(Date().timeIntervalSince1970) {
                    self.ageSubmission = (stored.order.orderHash, MeasuredAgeProof(proof: proof, timing: timing))
                    self.scheduleAgeExpiry(stored.order)
                }
                try self.check(ticket)
                // A saved success is rechecked against both providers before
                // being presented as success after a restart.
                try await self.recover(ticket)
                try await self.followPayment(ticket)
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
            guard try await ShopReadiness.waitForAvailability(check: { try await client.ready() }) else {
                throw ProductError.unavailable("The store cannot accept new orders right now. Nothing was paid.")
            }
            try self.check(ticket); self.canStart = true; self.phase = .review
        }
    }

    func startOrder(wallet: WalletService) {
        guard !busy, [.review, .funding].contains(phase), order == nil, canStart, client != nil, let connection else { return }
        guard let payer = wallet.ownerAddress else { message = "Connect your wallet first. No order has been sent."; return }
        phase = .checking; message = nil
        run { ticket in
            let primary = EthereumRPC(url: "https://rpc.testnet.arc.io", chainID: AgeShopProtocol.chainID)
            let independent = EthereumRPC(url: "https://rpc.drpc.testnet.arc.io", chainID: AgeShopProtocol.chainID)
            async let firstHeight = primary.finalizedShopHeight()
            async let secondHeight = independent.finalizedShopHeight()
            let heights = try await (firstHeight, secondHeight)
            let height = min(heights.0, heights.1)
            async let firstFunds = primary.shopFunds(payer: payer, blockNumber: height)
            async let secondFunds = independent.shopFunds(payer: payer, blockNumber: height)
            let funds = try await (firstFunds, secondFunds)
            try self.check(ticket)
            guard wallet.ownerAddress?.lowercased() == payer.lowercased(), funds.0 == funds.1 else { throw ProductError.invalidResponse }
            guard funds.0.sufficient else {
                self.fundingAddress = payer; self.phase = .funding; return
            }
            self.fundingAddress = nil
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

    func readCard(pin: String, sensors: MateModel) {
        guard !busy, phase == .card, let saved, client != nil, JPKICardReader.validSigningPIN(pin) else { return }
        message = nil
        phase = .preparingCard
        run { ticket in
            try await sensors.stopCaptureAndWait()
            try self.check(ticket)
            let order = saved.order
            let challenge = try JPKIChallenge(orderHash: CanonicalBytes.hex(order.orderHash, count: 32),
                                               nonce: CanonicalBytes.hex(order.paymentNonce, count: 32))
            let credential = try await self.reader.authenticate(pin: pin, challenge: challenge,
                expiresAt: Date(timeIntervalSince1970: Double(order.expiresAt))) {
                    guard self.generation == ticket else { return }
                    self.phase = .readingCard
                }
            try self.check(ticket)
            self.ageAuthentication = (order.orderHash, credential.authentication)
            self.scheduleAgeExpiry(order)
            try await self.makeAgeProof(ticket)
        }
    }

    private func makeAgeProof(_ ticket: UUID) async throws {
        guard let saved, let authentication = ageAuthentication,
              authentication.hash == saved.order.orderHash else { throw AgeShopError.invalidOrder }
        let order = saved.order
        phase = .proving; proofStartedAt = .now
        // If iOS closes the process, recovery must not misrepresent this attempt
        // as a bad card/password. This marker contains no card information.
        try recordAgeFailure(.interrupted)
        let proof = try await prover.prove(authentication: authentication.value,
            orderHash: CanonicalBytes.hex(order.orderHash, count: 32), nonce: CanonicalBytes.hex(order.paymentNonce, count: 32),
            referenceTime: order.createdAt, expiresAt: order.expiresAt)
        try check(ticket); proofStartedAt = nil
        ageAuthentication = nil
        ageSubmission = (order.orderHash, proof)
        guard var local = self.saved, local.order.orderHash == order.orderHash else { throw AgeShopError.invalidOrder }
        local.locallyProvenOrderHash = order.orderHash; local.proofTiming = proof.timing; local.ageProofFailure = nil
        local.pendingAgeProof = proof.proof
        try LocalSecrets.write(local, key: storageKey); self.saved = local
        try await submitAgeProof(ticket)
    }

    private func submitAgeProof(_ ticket: UUID) async throws {
        guard let saved, let client, let submission = ageSubmission,
              submission.hash == saved.order.orderHash else { throw AgeShopError.invalidOrder }
        phase = .verifying
        let verified = try await client.verifyAge(order: saved.order, key: saved.key, proof: submission.value.proof)
        try check(ticket); try store(verified)
        clearAgeMemory(); phase = .paymentApproval; message = nil
    }

    var canRetryAgeProof: Bool {
        phase == .proofFailed && ageAuthentication?.hash == saved?.order.orderHash &&
        ageAuthentication != nil && (saved?.order.expiresAt ?? 0) > UInt64(Date().timeIntervalSince1970)
    }
    var canRetryAgeSubmission: Bool {
        phase == .verificationFailed && ageSubmission?.hash == saved?.order.orderHash &&
        ageSubmission != nil && (saved?.order.expiresAt ?? 0) > UInt64(Date().timeIntervalSince1970)
    }
    func retryAgeProof() {
        guard !busy, canRetryAgeProof else { return }
        message = nil
        run { ticket in try await self.makeAgeProof(ticket) }
    }
    func retryAgeSubmission() {
        guard !busy, canRetryAgeSubmission else { return }
        message = nil
        run { ticket in try await self.submitAgeProof(ticket) }
    }
    func restartCardRead() {
        guard !busy, phase == .proofFailed, !canRetryAgeProof,
              (saved?.order.expiresAt ?? 0) > UInt64(Date().timeIntervalSince1970) else { return }
        // Explicit choice after memory was discarded; never automatic PIN reuse.
        message = nil; phase = .card
    }
    private func recordAgeFailure(_ failure: AgeProofFailure) throws {
        guard var local = saved else { return }
        local.ageProofFailure = failure
        try LocalSecrets.write(local, key: storageKey); saved = local
    }
    private func scheduleAgeExpiry(_ order: AgeShopOrder) {
        ageExpiry?.cancel()
        let delay = max(0, Double(order.expiresAt) - Date().timeIntervalSince1970)
        ageExpiry = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self, self.saved?.order.orderHash == order.orderHash else { return }
            self.clearAgeMemory()
            if !self.busy && [.proofFailed, .verificationFailed].contains(self.phase) {
                self.phase = .unavailable; self.message = AgeProofFailure.orderWindow.explanation
            }
        }
    }
    private func clearAgeMemory() {
        ageAuthentication = nil; ageSubmission = nil; ageExpiry?.cancel(); ageExpiry = nil
    }

    func continuePayment(wallet: WalletService) {
        guard !busy, phase == .paymentApproval else { return }
        run { ticket in try await self.signAndPay(wallet: wallet, ticket: ticket) }
    }

    private func signAndPay(wallet: WalletService, ticket: UUID) async throws {
        guard let client, let saved, saved.paymentHeader == nil, saved.paymentRetiredAtBlockHash == nil,
              Self.hasLocalProof(saved.order, marker: saved.locallyProvenOrderHash),
              saved.order.state == .ageVerified else { throw ProductError.invalidResponse }
        let required = try await client.paymentChallenge(order: saved.order, key: saved.key)
        try check(ticket)
        let signature = try await wallet.signShopPayment(order: saved.order, required: required) {
            try self.check(ticket)
            guard self.saved?.order.orderHash == saved.order.orderHash, self.saved?.paymentHeader == nil,
                  Self.hasLocalProof(saved.order, marker: self.saved?.locallyProvenOrderHash),
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
            try await followPayment(ticket)
            return
        }
        try await recover(ticket)
        try await followPayment(ticket)
    }

    func checkOrder() {
        guard saved != nil, !busy else { return }
        phase = .checking
        run { ticket in try await self.recover(ticket); try await self.followPayment(ticket) }
    }
    private func followPayment(_ ticket: UUID) async throws {
        guard phase == .pending else { return }
        message = "Checking the original payment. Its order and nonce are preserved."
        let leftPending = try await ShopConfirmation.observe(check: {
            try self.check(ticket)
            try await self.recover(ticket)
            return self.phase != .pending
        })
        try check(ticket)
        if !leftPending && phase == .pending {
            message = "The payment result is not confirmed yet. Check this same order; do not create another payment."
        }
    }
    private func recover(_ ticket: UUID) async throws {
        guard let client, let saved else { throw ProductError.invalidResponse }
        let current = try await client.status(order: saved.order, key: saved.key)
        try check(ticket); try store(current)
        if current.state == .complete {
            phase = .pending
            guard Self.hasLocalProof(current, marker: saved.locallyProvenOrderHash) else { throw AgeShopError.invalidOrder }
            async let primary = EthereumRPC(url: "https://rpc.testnet.arc.io", chainID: AgeShopProtocol.chainID).confirmShop(current)
            async let independent = EthereumRPC(url: "https://rpc.drpc.testnet.arc.io", chainID: AgeShopProtocol.chainID).confirmShop(current)
            let hashes = try await (primary, independent)
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
            let primary = EthereumRPC(url: "https://rpc.testnet.arc.io", chainID: AgeShopProtocol.chainID)
            let independent = EthereumRPC(url: "https://rpc.drpc.testnet.arc.io", chainID: AgeShopProtocol.chainID)
            async let firstHeight = primary.finalizedShopHeight()
            async let secondHeight = independent.finalizedShopHeight()
            let heights = try await (firstHeight, secondHeight)
            let height = min(heights.0, heights.1)
            async let first = primary.confirmUnusedShop(current, validBefore: end, blockNumber: height)
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
        } else if current.state == .ageVerified && Self.hasLocalProof(current, marker: saved.locallyProvenOrderHash) { phase = .paymentApproval }
        else {
            phase = recoverablePhase
            if phase == .proofFailed { message = self.saved?.ageProofFailure?.explanation }
            if phase == .verificationFailed { message = "Your age proof was made, but the store has not confirmed it. Nothing was paid." }
        }
    }

    func retryOriginalPayment() {
        guard !busy, phase == .pending, let saved, let header = saved.paymentHeader,
              let expires = saved.paymentExpiresAt, expires > UInt64(Date().timeIntervalSince1970), let client else { return }
        phase = .paying; message = nil
        run { ticket in
            let next = try await client.pay(order: saved.order, key: saved.key, header: header)
            try self.check(ticket); try self.store(next); try await self.recover(ticket)
            try await self.followPayment(ticket)
        }
    }
    var canRetryOriginal: Bool {
        phase == .pending && saved?.paymentHeader != nil && (saved?.paymentExpiresAt ?? 0) > UInt64(Date().timeIntervalSince1970)
    }
    private func store(_ order: AgeShopOrder) throws {
        guard var saved, saved.order.orderHash == order.orderHash else { throw AgeShopError.invalidOrder }
        if order.state != .awaitingAge || order.expiresAt <= UInt64(Date().timeIntervalSince1970) { saved.pendingAgeProof = nil }
        saved.order = order; try LocalSecrets.write(saved, key: storageKey)
        self.saved = saved; self.order = order
    }
    private func run(_ body: @escaping @MainActor (UUID) async throws -> Void) {
        guard operation == nil else { return }
        let ticket = UUID(); generation = ticket
        operation = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == ticket { self.operation = nil; self.proofStartedAt = nil } }
            do { try await body(ticket) }
            catch is CancellationError { }
            catch {
                guard self.generation == ticket else { return }
                if self.phase == .proving {
                    let failure = AgeProofFailure.classify(error)
                    // State already holds an interrupted marker if this save
                    // fails. Do not expose the persistence error or card input.
                    try? self.recordAgeFailure(failure)
                    self.message = failure.explanation; self.phase = .proofFailed
                } else if self.phase == .verifying {
                    self.message = "Your age proof was made, but the store has not confirmed it. Nothing was paid."
                    self.phase = .verificationFailed
                } else {
                    self.message = Self.explanation(error)
                    self.phase = self.recoverablePhase
                }
                // Restoring/checking can lose its first response too. Only
                // an outstanding payment receives bounded read-only follow-up;
                // PIN entry and payment approval are never retried here.
                if self.phase == .pending { try? await self.followPayment(ticket) }
            }
        }
    }
    private func check(_ ticket: UUID) throws {
        try Task.checkCancellation(); guard generation == ticket else { throw CancellationError() }
    }
    func cancel() {
        if [.card, .preparingCard, .readingCard].contains(phase) {
            message = Self.explanation(CardScanError.cancelled)
        }
        generation = UUID(); operation?.cancel(); operation = nil; reader.cancel()
        clearAgeMemory()
        proofStartedAt = nil
        // Saved payment state intentionally survives closing/backgrounding.
        // Foregrounding may check status, but must never resume PIN use or sign.
        phase = .initial; canStart = false
    }
    static func hasLocalProof(_ order: AgeShopOrder, marker: String?) -> Bool {
        guard let marker, (try? CanonicalBytes.hex(marker, count: 32)) != nil else { return false }
        return marker.lowercased() == order.orderHash.lowercased()
    }
    private var recoverablePhase: Phase {
        guard let saved else { return .unavailable }
        return Self.recoveryPhase(saved, now: UInt64(Date().timeIntervalSince1970))
    }
    static func recoveryPhase(_ saved: SavedShopOrder, now: UInt64) -> Phase {
        if saved.paymentRetiredAtBlockHash != nil { return .pending }
        if saved.paymentHeader != nil || [.paymentPending, .paymentExpired, .complete].contains(saved.order.state) { return .pending }
        if saved.order.expiresAt <= now { return .unavailable }
        if saved.ageProofFailure != nil { return .proofFailed }
        if saved.order.state == .awaitingAge && Self.hasLocalProof(saved.order, marker: saved.locallyProvenOrderHash) { return .verificationFailed }
        return saved.order.state == .ageVerified && Self.hasLocalProof(saved.order, marker: saved.locallyProvenOrderHash) ? .paymentApproval : .card
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
                var history = try LocalSecrets.read([SavedShopOrder].self, key: "arc-testnet-shop-history") ?? []
                history.append(saved); try LocalSecrets.write(Array(history.suffix(20)), key: "arc-testnet-shop-history")
            }
            try LocalSecrets.delete(storageKey)
            try LocalSecrets.delete(creationKey)
            clearAgeMemory(); saved = nil; order = nil; message = nil; phase = .initial; load()
        } catch { message = Self.explanation(error) }
    }
    static func explanation(_ error: Error) -> String {
        if let error = error as? AgeProofFailure { return error.explanation }
        if let card = error as? MyNumberCardError {
            switch card {
            case .pinRejected(let attempts): return L10n.format("The signature password was rejected. %lld attempts remain. Mate did not retry.", Int64(attempts))
            case .pinBlocked: return "The card PIN is locked. Mate made no further attempt."
            case .requestExpired: return "This order expired. Mate stopped the card step. Start a new order."
            default: return "The card could not be read. No personal information was sent."
            }
        }
        if error is JPKIVerificationError || error is JPKIAgeWitnessError {
            return "This card could not be authenticated for this order on the phone. No card information was sent."
        }
        if let error = error as? CameraError { return error.localizedDescription }
        if let error = error as? CardScanError {
            switch error {
            case .unavailable: return "Physical card scanning is not available on this device."
            case .permissionMissing: return "This app's NFC permission is missing. The app must be reinstalled with card-reading support. No card PIN was checked."
            case .busy: return "The iPhone could not start NFC while another operation was using it. Mate stopped its camera. Enter the signature password and tap Start card scan to try again."
            case .activationTimedOut: return "The card scanner did not open. Close Mate and reopen it, then try again. Your PIN was cleared without retrying."
            case .timedOut: return "The card scan timed out. Enter the signature password and tap Start card scan when your card is ready."
            case .cancelled: return "Card scanning stopped. Your PIN was cleared. Enter it again and tap Start card scan when you're ready."
            default: return "The card scan did not finish. Your PIN was cleared. Enter it again and tap Start card scan to retry."
            }
        }
        if error is AgeShopError { return "The order or payment details could not be verified. No new payment was authorized." }
        if let error = error as? ProductError { return error.localizedDescription }
        return "This step could not be completed. Your existing order was kept; no replacement payment was created."
    }
}


extension ShopCheckout.Phase {
    /// Brief speech follows verified state transitions; it never announces a
    /// successful proof or payment merely because a spinner or timer finished.
    var spokenGuide: String? {
        switch self {
        case .review: return "I’ll get one beer. First, let’s confirm your age."
        case .card: return "Enter your card’s signature password, then tap Start card scan."
        case .funding: return "Your wallet needs free test USDC before I can order."
        case .proving: return "Card read. I’m making your age proof on this iPhone."
        case .proofFailed: return "The card was read, but I couldn't finish the age proof. Your purchase is not complete."
        case .verificationFailed: return "Your age proof is ready, but the store hasn't confirmed it. Your purchase is not complete."
        case .verifying: return "Your proof is ready. The store is checking it."
        case .paymentApproval: return "Age verified. Please approve this one payment on your iPhone."
        case .pending: return "The payment is still being checked. I’ll keep this order."
        case .complete: return "Your beer purchase is complete. Your birth date stayed on this iPhone."
        case .expired: return "This order expired. Please start a new order."
        case .unavailable: return "I couldn’t continue the order. Please check the message on screen."
        default: return nil
        }
    }
}
