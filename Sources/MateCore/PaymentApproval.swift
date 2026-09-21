import Foundation

/// Immutable terms displayed by a trusted approval UI. Neither a model nor a
/// merchant receives the approver or signer. Nonces must come from a CSPRNG.
public struct PaymentApproval: Codable, Equatable, Sendable {
    public let id: UUID
    public let request: PaymentRequest
    public let authorization: PaymentAuthorization
    public let createdAt: UInt64

    public init(request: PaymentRequest, payer: String, nonce: String, now: UInt64) throws {
        id = UUID(); self.request = request; createdAt = now
        authorization = try PaymentAuthorization(request: request, payer: payer, nonce: nonce, now: now)
    }
    public func validate(now: UInt64) throws {
        try request.validate(now: now)
        try authorization.validate(request: request)
        guard createdAt <= UInt64.max - 300, createdAt <= now, authorization.validBefore == String(createdAt + UInt64(request.accepted.maxTimeoutSeconds))
        else { throw ExternalPaymentError.invalidAuthorization }
    }
}

public protocol PaymentJournal: Sendable {
    /// An unfinished approval/signing attempt throws instead of appearing empty.
    func load() async throws -> PendingPayment?
    func reserve(_ pending: PendingPayment) async throws
}
public protocol PaymentApprovalJournal: PaymentJournal {
    func beginApproval(_ approval: PaymentApproval) async throws
    func beginSigning(_ approval: PaymentApproval) async throws
    func finishSigning(_ pending: PendingPayment, approval: PaymentApproval) async throws
    /// Only the same, still-unsigned approval may be released by its coordinator.
    func cancelApproval(_ approval: PaymentApproval) async throws
}

/// One persisted record, transitioned atomically by its owning journal actor.
/// A crash during approval or signing remains locked on restart. Expiry cannot
/// clear a signing attempt: the provider may have produced a valid signature.
public struct PaymentJournalState: Codable, Equatable, Sendable {
    public enum Entry: Codable, Equatable, Sendable {
        case approving(PaymentApproval), signing(PaymentApproval), signed(PendingPayment)
    }
    public private(set) var entry: Entry?
    public init() { entry = nil }
    private enum CodingKeys: String, CodingKey { case version, entry }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if c.contains(.version) {
            guard c.contains(.entry), try c.decode(Int.self, forKey: .version) == 1 else { throw ExternalPaymentError.unresolvedPayment }
            entry = try c.decodeIfPresent(Entry.self, forKey: .entry)
        } else {
            // Preserve the previous journal's bare PendingPayment; never reset it.
            entry = .signed(try PendingPayment(from: decoder))
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(1, forKey: .version); try c.encode(entry, forKey: .entry)
    }
    public func pending() throws -> PendingPayment? {
        switch entry {
        case nil: return nil
        case .signed(let payment): return payment
        default: throw ExternalPaymentError.unresolvedPayment
        }
    }
    public mutating func reserve(_ payment: PendingPayment) throws {
        if let entry {
            guard entry == .signed(payment) else { throw ExternalPaymentError.unresolvedPayment }
        } else { entry = .signed(payment) }
    }
    public mutating func beginApproval(_ approval: PaymentApproval) throws {
        guard entry == nil else { throw ExternalPaymentError.unresolvedPayment }
        entry = .approving(approval)
    }
    public mutating func beginSigning(_ approval: PaymentApproval) throws {
        guard entry == .approving(approval) else { throw ExternalPaymentError.unresolvedPayment }
        entry = .signing(approval)
    }
    public mutating func finishSigning(_ payment: PendingPayment, approval: PaymentApproval) throws {
        guard entry == .signing(approval), payment.request == approval.request,
              payment.authorization == approval.authorization else { throw ExternalPaymentError.unresolvedPayment }
        entry = .signed(payment)
    }
    public mutating func cancelApproval(_ approval: PaymentApproval) throws {
        guard entry == .approving(approval) else { throw ExternalPaymentError.unresolvedPayment }
        entry = nil
    }
}

/// Separate capabilities: approving must never sign; signing must use exactly
/// these terms; verification must locally recover the EIP-712 payer. Concrete
/// wallet/approval/recovery adapters are not enabled by these interfaces.
public protocol ExternalPaymentApprover: Sendable {
    func approve(_ approval: PaymentApproval) async throws
}
public protocol ExternalPaymentSigner: Sendable {
    func sign(_ approval: PaymentApproval) async throws -> String
}
public protocol ExternalPaymentSignatureVerifier: Sendable {
    func verify(_ signature: String, approval: PaymentApproval) async throws
}

public actor PaymentApprovalCoordinator {
    private let journal: any PaymentApprovalJournal
    private let now: @Sendable () -> UInt64
    public init(journal: any PaymentApprovalJournal, now: @escaping @Sendable () -> UInt64) {
        self.journal = journal; self.now = now
    }
    public func approve(_ terms: PaymentApproval, with approver: any ExternalPaymentApprover,
                        signer: any ExternalPaymentSigner, verifier: any ExternalPaymentSignatureVerifier) async throws -> PendingPayment {
        try Task.checkCancellation()
        try terms.validate(now: now())
        // Shared durable gate, including across multiple coordinators. Even an
        // identical concurrent approval cannot prompt or invoke the signer twice.
        try await journal.beginApproval(terms)
        do {
            try Task.checkCancellation()
            try await approver.approve(terms)
            try Task.checkCancellation()
            try terms.validate(now: now())
        } catch {
            // No signer has been called in this scope. Storage failure stays locked.
            try await journal.cancelApproval(terms)
            throw error
        }
        // Persist uncertainty BEFORE the provider can create a signature. Nothing
        // after this point, including cancellation/expiry, releases the barrier.
        try await journal.beginSigning(terms)
        try Task.checkCancellation()
        try terms.validate(now: now())
        let signature = try await signer.sign(terms)
        // The result can arrive after the quote expires. Preserve its original
        // signed window rather than constructing a fresh authorization or dropping it.
        let pending = try PendingPayment(request: terms.request, authorization: terms.authorization,
                                         signature: signature, now: terms.createdAt)
        try await verifier.verify(signature, approval: terms)
        try await journal.finishSigning(pending, approval: terms)
        try Task.checkCancellation()
        return pending
    }
}
