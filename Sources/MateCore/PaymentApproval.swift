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

public protocol RecoverablePaymentJournal: PaymentApprovalJournal {
    func snapshot() async throws -> PaymentJournalState
    func observe(_ payment: PendingPayment, response: PaymentObservation) async throws
    /// Caller must first corroborate settlement independently of the merchant.
    func complete(_ payment: PendingPayment, completion: PaymentCompletion) async throws
    func expire(_ entry: PaymentJournalState.Entry, evidence: ExpiredPaymentEvidence) async throws
}

/// Corroborated finalized RPC state, not elapsed wall-clock time or an HTTP error.
public struct ExpiredPaymentEvidence: Codable, Equatable, Sendable {
    public let authorization: PaymentAuthorization
    public let blockHash: String
    public let blockNumber: UInt64
    public let timestamp: UInt64
    public init(authorization: PaymentAuthorization, blockHash: String, blockNumber: UInt64, timestamp: UInt64) throws {
        guard let end = UInt64(authorization.validBefore), timestamp >= end, blockNumber > 0,
              (try CanonicalBytes.hex(blockHash, count: 32)).contains(where: { $0 != 0 }) else {
            throw ExternalPaymentError.invalidReceipt
        }
        self.authorization = authorization; self.blockHash = blockHash
        self.blockNumber = blockNumber; self.timestamp = timestamp
    }
}

public struct PaymentObservation: Codable, Equatable, Sendable {
    public let status: Int
    public let body: Data
    public let claim: PaymentReceipt?
    public init(status: Int, body: Data, claim: PaymentReceipt?) throws {
        guard (200...599).contains(status), body.count <= 65_536 else { throw ExternalPaymentError.invalidReceipt }
        self.status = status; self.body = body; self.claim = claim
    }
}

/// Local history contains no reusable signature. Receiving an HTTP result and
/// confirming a token transfer are recorded separately.
public struct PaymentCompletion: Codable, Equatable, Sendable, Identifiable {
    public var id: String { authorization.from.lowercased() + ":" + authorization.nonce.lowercased() }
    public let request: PaymentRequest
    public let authorization: PaymentAuthorization
    public let transaction: String
    public let blockHash: String
    public let blockNumber: UInt64
    public let completedAt: UInt64
    public let response: Data?
    public let httpStatus: Int?

    public init(payment: PendingPayment, transaction: String, blockHash: String, blockNumber: UInt64,
                now: UInt64, response: Data? = nil, httpStatus: Int? = nil) throws {
        try payment.validate(now: now, allowExpired: true)
        guard (try CanonicalBytes.hex(transaction, count: 32)).contains(where: { $0 != 0 }),
              (try CanonicalBytes.hex(blockHash, count: 32)).contains(where: { $0 != 0 }),
              blockNumber > 0, (response?.count ?? 0) <= 65_536,
              httpStatus == nil || (200...599).contains(httpStatus!),
              response == nil || httpStatus != nil else { throw ExternalPaymentError.invalidReceipt }
        request = payment.request; authorization = payment.authorization
        self.transaction = transaction.lowercased(); self.blockHash = blockHash.lowercased()
        self.blockNumber = blockNumber; completedAt = now
        self.response = response; self.httpStatus = httpStatus
    }
    public var receivedResult: Bool {
        response != nil && httpStatus.map { (200...299).contains($0) } == true
    }
}

/// One persisted record, transitioned atomically by its owning journal actor.
/// A crash during approval or signing remains locked on restart. Expiry cannot
/// clear a signing attempt: the provider may have produced a valid signature.
public struct PaymentJournalState: Codable, Equatable, Sendable {
    public enum Entry: Codable, Equatable, Sendable {
        case approving(PaymentApproval), signing(PaymentApproval), signed(PendingPayment)
    }
    public private(set) var entry: Entry?
    public private(set) var history: [PaymentCompletion] = []
    public private(set) var observation: PaymentObservation?
    public private(set) var expired: [ExpiredPaymentEvidence] = []
    public init() { entry = nil }
    private enum CodingKeys: String, CodingKey { case version, entry, history, observation, expired }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if c.contains(.version) {
            let version = try c.decode(Int.self, forKey: .version)
            guard c.contains(.entry), version == 1 || version == 2 else { throw ExternalPaymentError.unresolvedPayment }
            entry = try c.decodeIfPresent(Entry.self, forKey: .entry)
            if version == 2 {
                history = try c.decode([PaymentCompletion].self, forKey: .history)
                observation = try c.decodeIfPresent(PaymentObservation.self, forKey: .observation)
                expired = try c.decodeIfPresent([ExpiredPaymentEvidence].self, forKey: .expired) ?? []
                guard history.count <= 20, expired.count <= 20 else { throw ExternalPaymentError.unresolvedPayment }
            }
        } else {
            // Preserve the previous journal's bare PendingPayment; never reset it.
            entry = .signed(try PendingPayment(from: decoder))
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(2, forKey: .version); try c.encode(entry, forKey: .entry)
        try c.encode(history, forKey: .history)
        try c.encodeIfPresent(observation, forKey: .observation)
        try c.encode(expired, forKey: .expired)
    }
    public func pending() throws -> PendingPayment? {
        switch entry {
        case nil: return nil
        case .signed(let payment): return payment
        default: throw ExternalPaymentError.unresolvedPayment
        }
    }
    public mutating func reserve(_ payment: PendingPayment) throws {
        try rejectCompleted(payment.authorization)
        if let entry {
            guard entry == .signed(payment) else { throw ExternalPaymentError.unresolvedPayment }
        } else { entry = .signed(payment) }
    }
    public mutating func beginApproval(_ approval: PaymentApproval) throws {
        try rejectCompleted(approval.authorization)
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
    public mutating func complete(_ payment: PendingPayment, completion: PaymentCompletion) throws {
        guard completion.request == payment.request, completion.authorization == payment.authorization else {
            throw ExternalPaymentError.invalidReceipt
        }
        if history.contains(completion) { return } // A late repeat cannot clear a newer entry.
        guard entry == .signed(payment) else { throw ExternalPaymentError.unresolvedPayment }
        history.insert(completion, at: 0)
        history = Array(history.prefix(20))
        entry = nil; observation = nil
    }
    public mutating func observe(_ payment: PendingPayment, response: PaymentObservation) throws {
        guard entry == .signed(payment), response.body.count <= 65_536,
              (200...599).contains(response.status) else { throw ExternalPaymentError.unresolvedPayment }
        if let claim = response.claim {
            try claim.validate(pending: payment, now: UInt64(payment.authorization.validBefore) ?? 0)
        }
        // A later retry error must not discard the already received result/locator.
        if let previous = observation, (200...299).contains(previous.status) {
            observation = try PaymentObservation(status: previous.status, body: previous.body, claim: previous.claim ?? response.claim)
            return
        }
        observation = try PaymentObservation(status: response.status, body: response.body, claim: response.claim ?? observation?.claim)
    }
    public mutating func expire(_ expected: Entry, evidence: ExpiredPaymentEvidence) throws {
        let authorization: PaymentAuthorization
        switch expected {
        case .signed(let payment): authorization = payment.authorization
        case .signing(let approval): authorization = approval.authorization
        case .approving: throw ExternalPaymentError.unresolvedPayment
        }
        guard entry == expected, authorization == evidence.authorization,
              let end = UInt64(authorization.validBefore), evidence.timestamp >= end,
              evidence.blockNumber > 0,
              (try CanonicalBytes.hex(evidence.blockHash, count: 32)).contains(where: { $0 != 0 }) else {
            throw ExternalPaymentError.unresolvedPayment
        }
        expired.insert(evidence, at: 0); expired = Array(expired.prefix(20))
        entry = nil; observation = nil
    }
    private func rejectCompleted(_ authorization: PaymentAuthorization) throws {
        guard !(history.map(\.authorization) + expired.map(\.authorization)).contains(where: {
            $0.from.lowercased() == authorization.from.lowercased()
                && $0.nonce.lowercased() == authorization.nonce.lowercased()
        }) else { throw ExternalPaymentError.unresolvedPayment }
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
    func verify(_ signature: String, approval: PaymentApproval) throws
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
        // A local verifier may check task cancellation itself. Complete this
        // bounded, non-network recovery/write in an uncanceled task so an already
        // returned signature is retained before reporting caller cancellation.
        // This task cannot approve, sign or transmit another payment.
        let journal = self.journal
        try await Task.detached {
            try verifier.verify(signature, approval: terms)
            try await journal.finishSigning(pending, approval: terms)
        }.value
        try Task.checkCancellation()
        return pending
    }
}
