import Foundation
import Combine
import MateCore

struct ConnectedPaymentService: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let payment: PaymentService
    init(name: String, payment: PaymentService) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 60, !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw ExternalPaymentError.invalidService
        }
        _ = try payment.validate()
        id = UUID(); self.name = name; self.payment = payment
    }
}

@MainActor
final class ConnectedPaymentServices: ObservableObject {
    static let shared = ConnectedPaymentServices()
    @Published private(set) var services: [ConnectedPaymentService] = []
    private let key = "external-payment-services-v1"
    func load() throws {
        let saved = try LocalSecrets.read([ConnectedPaymentService].self, key: key) ?? []
        guard saved.count <= 20 else { throw ExternalPaymentError.invalidService }
        for service in saved { _ = try service.payment.validate() }
        services = saved
    }
    func add(name: String, quote: PaymentRequest) throws {
        try quote.validate(now: UInt64(Date().timeIntervalSince1970))
        guard services.count < 20, !services.contains(where: { $0.payment.resource == quote.service.resource }) else {
            throw ExternalPaymentError.invalidService
        }
        let value = try ConnectedPaymentService(name: name, payment: quote.service)
        let next = services + [value]
        try LocalSecrets.write(next, key: key); services = next
    }
    func remove(_ service: ConnectedPaymentService) throws {
        let next = services.filter { $0.id != service.id }
        try LocalSecrets.write(next, key: key); services = next
    }
}

@MainActor
final class ExternalCheckout: ObservableObject {
    @Published private(set) var busy = false
    @Published private(set) var quote: PaymentRequest?
    @Published private(set) var pending: PendingPayment?
    @Published private(set) var stalled: PaymentApproval?
    @Published private(set) var signingUncertain = false
    @Published private(set) var completion: PaymentCompletion?
    @Published private(set) var history: [PaymentCompletion] = []
    @Published private(set) var error: String?
    @Published private(set) var phase = "Connected services"
    private let journal = DevicePaymentJournal.shared
    private let checker = ExternalPaymentReconciliation()
    private var operation: Task<Void, Never>?
    private var now: UInt64 { UInt64(Date().timeIntervalSince1970) }

    func restore() async {
        do {
            try ConnectedPaymentServices.shared.load()
            let saved = try await journal.snapshot()
            history = saved.history; pending = nil; stalled = nil; signingUncertain = false
            switch saved.entry {
            case .signed(let payment): pending = payment; phase = "Check the previous payment"
            case .approving(let approval): stalled = approval; phase = "An unfinished approval"
            case .signing(let approval): stalled = approval; signingUncertain = true; phase = "Check the previous payment"
            case nil: if completion == nil { phase = quote == nil ? "Connected services" : "Review this payment" }
            }
        } catch { self.error = L10n.text("Saved payment state could not be read. No new payment can be made.") }
    }

    /// Only durable local state speaks for a payment. Merchant text and a
    /// previous shop order cannot make a new external request sound successful.
    static func savedPaymentAnswer() async -> String {
        do {
            let state = try await DevicePaymentJournal.shared.snapshot()
            switch state.entry {
            case .approving:
                return "Your service payment is waiting for approval. Nothing has been signed."
            case .signing, .signed:
                return "Your service payment is not confirmed yet. Open Connected services to check the original payment."
            case nil:
                if let latest = state.history.first {
                    return latest.receivedResult
                        ? "Your most recently completed service payment is confirmed on Arc. Its result is saved in Connected services."
                        : "Your most recently completed service payment is confirmed on Arc, but its result is unavailable. No new payment was made."
                }
                return "There is no confirmed service payment. Open Connected services to continue."
            }
        } catch {
            return "Saved payment state could not be read. No new payment can be made."
        }
    }

    func discover(resource: String, maximum: UInt64) async throws -> PaymentRequest {
        try await ExternalPaymentClient(resource: resource).discover(maximumAmount: maximum, now: now)
    }

    func prepare(_ service: ConnectedPaymentService) {
        run {
            let state = try await self.journal.snapshot()
            guard state.entry == nil else { throw ExternalPaymentError.unresolvedPayment }
            self.completion = nil; self.quote = nil; self.phase = "Checking price"
            self.quote = try await ExternalPaymentClient(service: service.payment).quote(now: self.now)
            self.phase = "Review this payment"
        }
    }

    func approve(wallet: WalletService) {
        guard let quote else { return }
        run {
            guard let payer = wallet.ownerAddress else { throw ProductError.unavailable("Connect your buyer wallet first.") }
            try quote.validate(now:self.now)
            guard let amount=UInt64(quote.accepted.amount) else{throw ExternalPaymentError.invalidAuthorization}
            self.phase = "Checking the payment on Arc"
            switch try await self.checker.funds(payer:payer,amount:amount) {
            case .sufficient: break
            case .insufficient: throw ProductError.unavailable("Your buyer wallet needs more test USDC. Use the faucet below, then approve again.")
            case .unavailable: throw ProductError.unavailable("The wallet balance could not be checked. Nothing was signed. Please try again.")
            }
            let terms = try PaymentApproval(request: quote, payer: payer,
                nonce: CanonicalBytes.hexString(LocalSecrets.random32()), now: self.now)
            self.phase = "Approve this payment"
            let coordinator = PaymentApprovalCoordinator(journal: self.journal,
                now: { UInt64(Date().timeIntervalSince1970) })
            let signed = try await coordinator.approve(terms, with: DevicePaymentApprover(),
                signer: PrivyPaymentSigner(wallet: wallet), verifier: PaymentSignatureVerifier())
            self.pending = signed; self.quote = nil
            try await self.submit(signed)
        }
    }

    func retry() {
        guard let pending else { return }
        run { try await self.submit(pending) }
    }

    func check(transaction: String? = nil) {
        run {
            guard let pending = try await self.journal.load() else { throw ExternalPaymentError.unresolvedPayment }
            let claim = try transaction.map {
                try PaymentReceipt.unverifiedLocator($0, pending: pending, now: self.now)
            }
            self.phase = "Checking the payment on Arc"
            let result = try await ExternalPaymentRecovery(journal: self.journal).complete(
                using: self.checker, claim: claim, now: self.now)
            if let result { self.finished(result) }
            else { self.error = L10n.text("The payment is not confirmed yet. Its original authorization is retained.") }
        }
    }

    func cancelUnsignedApproval() {
        guard let stalled, !signingUncertain else { return }
        run { try await self.journal.cancelApproval(stalled); await self.restore() }
    }
    func releaseExpired() {
        run {
            self.phase = "Checking the payment on Arc"
            if try await ExternalPaymentRecovery(journal:self.journal).releaseExpired(using:self.checker) {
                self.quote = nil
                self.error = L10n.text("The authorization expired unused. You can start a new purchase.")
            } else {
                self.error = L10n.text("This authorization is still active, used, or could not be checked. No new payment was made.")
            }
        }
    }
    func remove(_ services: [ConnectedPaymentService]) {
        run { for service in services { try ConnectedPaymentServices.shared.remove(service) } }
    }
    func dismissQuote() { guard !busy else { return }; quote = nil; completion = nil; phase = "Connected services" }
    func cancel() { operation?.cancel() }

    private func submit(_ pending: PendingPayment) async throws {
        self.phase = "Requesting the service"
        let recovery = ExternalPaymentRecovery(journal: journal)
        _ = try await recovery.submit(pending, through: ExternalPaymentClient(service: pending.request.service), now: now)
        phase = "Checking the payment on Arc"
        for attempt in 0..<3 {
            if let result = try await recovery.complete(using: checker, claim: nil, now: now) {
                finished(result); return
            }
            if attempt < 2 { try await Task.sleep(for: .seconds(2)) }
        }
        error = L10n.text("The payment is not confirmed yet. Its original authorization is retained.")
    }
    private func finished(_ result: PaymentCompletion) {
        completion = result; pending = nil; stalled = nil; quote = nil
        phase = result.receivedResult ? "Payment confirmed · Result received" : "Payment confirmed · Result unavailable"
    }
    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true; error = nil
        operation = Task {
            do { try await action() }
            catch is CancellationError {} // Signed state remains recoverable.
            catch ProductError.unavailable(let message) { self.error = L10n.text(message) }
            catch {
                self.error = L10n.text("This request could not finish. Any existing payment is retained; nothing is retried with a new signature.")
            }
            await restore(); busy = false; operation = nil
        }
    }
}
