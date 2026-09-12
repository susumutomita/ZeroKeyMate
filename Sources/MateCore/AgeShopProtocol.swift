import Foundation

public enum AgeShopError: Error, Equatable, Sendable {
    case invalidConnection, invalidOrder, expiredOrder, invalidPayment
}

/// Configured by the owner/deployment, never by an LLM or shop response.
public struct AgeShopConnection: Codable, Equatable, Sendable {
    public let origin: String
    public let recipient: String
    public let ageGate: String
    public let ageGateCodeHash: String
    public init(origin: String, recipient: String, ageGate: String, ageGateCodeHash: String) {
        self.origin = origin; self.recipient = recipient; self.ageGate = ageGate; self.ageGateCodeHash = ageGateCodeHash
    }
    public func validate() throws -> URL {
        guard let url = URL(string: origin), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/", url.port == nil || url.port == 443 else { throw AgeShopError.invalidConnection }
        for (value, count) in [(recipient, 20), (ageGate, 20), (ageGateCodeHash, 32)] {
            guard try CanonicalBytes.hex(value, count: count).contains(where: { $0 != 0 }) else { throw AgeShopError.invalidConnection }
        }
        return url
    }
}

/// Server data is untrusted until validate() recomputes BOTH commitments.
public struct AgeShopOrder: Codable, Equatable, Sendable {
    public let id: String
    public let productId: String
    public let quantity: Int
    public let payer: String
    public let amount: String
    public let recipient: String
    public let chainId: UInt64
    public let token: String
    public let ageGate: String
    public let createdAt: UInt64
    public let expiresAt: UInt64
    public let minimumAge: Int
    public let state: State
    public let paymentTransaction: String?
    public let paymentValidBefore: UInt64?
    public let paymentNonce: String
    public let orderHash: String
    public enum State: String, Codable, Sendable { case awaitingAge = "awaiting_age", ageVerified = "age_verified", paymentPending = "payment_pending", paymentExpired = "payment_expired", complete }
}

public enum AgeShopProtocol {
    public static let chainID: UInt64 = 84532
    public static let token = "0x036cbd53842c5426634e7929541ec2318f3dcf7e"
    public static let amount = "100000"
    public static let network = "eip155:84532"

    /// No order status or model output is payment authority. The deterministic
    /// purchase UI must additionally approve this validated order and amount.
    public static func validate(_ order: AgeShopOrder, connection: AgeShopConnection, payer: String,
                                key: String, now: UInt64, allowExpired: Bool = false,
                                keccak: (Data) throws -> Data) throws {
        _ = try connection.validate()
        guard key.utf8.count == 64, key.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              try CanonicalBytes.hex(payer, count: 20).contains(where: { $0 != 0 }),
              order.chainId == chainID, order.token.lowercased() == token, order.productId == "mate-lager",
              order.quantity == 1, order.amount == amount, order.minimumAge == 20,
              order.payer.lowercased() == payer.lowercased(),
              order.recipient.lowercased() == connection.recipient.lowercased(),
              order.ageGate.lowercased() == connection.ageGate.lowercased(),
              order.expiresAt > order.createdAt, order.expiresAt - order.createdAt == 900,
              order.createdAt <= now else { throw AgeShopError.invalidOrder }
        if !allowExpired && order.expiresAt <= now { throw AgeShopError.expiredOrder }
        let id = try keccak(Data(key.utf8))
        guard id.count == 32, try CanonicalBytes.hex(order.id, count: 32) == id else { throw AgeShopError.invalidOrder }
        let nonce = try keccak(abi([.text("ZKM-X402-ORDER-1"), .bytes32(id)]))
        guard nonce.count == 32, try CanonicalBytes.hex(order.paymentNonce, count: 32) == nonce,
              try CanonicalBytes.hex(order.orderHash, count: 32) == keccak(orderMaterial(order)) else { throw AgeShopError.invalidOrder }
        if let transaction = order.paymentTransaction { _ = try CanonicalBytes.hex(transaction, count: 32) }
        if order.state == .complete && order.paymentTransaction == nil { throw AgeShopError.invalidOrder }
        if let end = order.paymentValidBefore {
            guard end > order.createdAt, end <= order.expiresAt else { throw AgeShopError.invalidPayment }
        }
        if order.state == .paymentExpired && order.paymentValidBefore == nil { throw AgeShopError.invalidPayment }
    }

    public static func orderMaterial(_ order: AgeShopOrder) throws -> Data {
        guard let value = UInt64(order.amount), order.quantity == 1, order.minimumAge == 20 else { throw AgeShopError.invalidOrder }
        return try abi([.text("ZKM-AGE-ORDER-1"), .integer(order.chainId), .address(order.ageGate),
            .bytes32(CanonicalBytes.hex(order.id, count: 32)), .text(order.productId), .integer(1),
            .address(order.payer), .address(order.recipient), .address(order.token), .integer(value),
            .integer(order.expiresAt), .bytes32(CanonicalBytes.hex(order.paymentNonce, count: 32)), .integer(20)])
    }

    // The small ABI subset used by the published shop protocol. Keccak itself
    // is supplied by the pinned RustCrypto implementation, not reimplemented.
    enum Word { case text(String), integer(UInt64), address(String), bytes32(Data) }
    static func abi(_ words: [Word]) throws -> Data {
        func uint(_ value: UInt64) -> Data { Data(repeating: 0, count: 24) + CanonicalBytes.u64(value) }
        var head = Data(), tail = Data()
        for word in words {
            switch word {
            case .integer(let value): head.append(uint(value))
            case .address(let value): head.append(Data(repeating: 0, count: 12) + (try CanonicalBytes.hex(value, count: 20)))
            case .bytes32(let value):
                guard value.count == 32 else { throw AgeShopError.invalidOrder }; head.append(value)
            case .text(let value):
                let bytes = Data(value.utf8)
                guard bytes.count <= 128 else { throw AgeShopError.invalidOrder }
                head.append(uint(UInt64(words.count * 32 + tail.count)))
                tail.append(uint(UInt64(bytes.count))); tail.append(bytes)
                tail.append(Data(repeating: 0, count: (32 - bytes.count % 32) % 32))
            }
        }
        return head + tail
    }
}
