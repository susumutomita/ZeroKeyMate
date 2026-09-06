import Foundation

public enum MandateError: Error, LocalizedError, Equatable, Sendable {
    case invalidAmount, invalidHex, invalidPolicy, invalidAction, overBudget, serviceNotAllowed
    public var errorDescription: String? {
        switch self {
        case .invalidAmount: return "金額は正の数で、小数点以下6桁までにしてください。"
        case .invalidHex: return "アドレスまたは識別子の形式が正しくありません。"
        case .invalidPolicy: return "委任条件が正しくありません。"
        case .invalidAction: return "実行内容が正しくありません。"
        case .overBudget: return "この依頼は、承認済みの利用上限を超えます。"
        case .serviceNotAllowed: return "この種類の依頼は許可されていません。"
        }
    }
}

public enum CanonicalBytes {
    public static func hex(_ value: String, count: Int) throws -> Data {
        guard value.hasPrefix("0x"), value.utf8.count == 2 + count * 2 else { throw MandateError.invalidHex }
        let chars = Array(value.utf8.dropFirst(2))
        func nibble(_ char: UInt8) throws -> UInt8 {
            switch char {
            case 48...57: return char - 48
            case 65...70: return char - 55
            case 97...102: return char - 87
            default: throw MandateError.invalidHex
            }
        }
        var result = Data(); result.reserveCapacity(count)
        for offset in stride(from: 0, to: chars.count, by: 2) {
            result.append(try nibble(chars[offset]) * 16 + nibble(chars[offset + 1]))
        }
        return result
    }
    public static func u64(_ value: UInt64) -> Data {
        Data((0..<8).map { UInt8(truncatingIfNeeded: value >> ((7 - $0) * 8)) })
    }
    public static func hexString(_ value: Data) -> String {
        "0x" + value.map { String(format: "%02x", $0) }.joined()
    }
}

public struct TokenAmount: Equatable, Sendable {
    public let units: UInt64
    public init(units: UInt64) { self.units = units }
    public init(decimal: String) throws {
        let pieces = decimal.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 1 || pieces.count == 2,
              let wholePart = pieces.first, !wholePart.isEmpty,
              wholePart.utf8.allSatisfy({ (48...57).contains($0) }),
              wholePart.count == 1 || wholePart.first != "0",
              let whole = UInt64(wholePart) else { throw MandateError.invalidAmount }
        let fraction = pieces.count == 2 ? String(pieces[1]) : ""
        guard fraction.count <= 6, (pieces.count == 1 || !fraction.isEmpty),
              fraction.utf8.allSatisfy({ (48...57).contains($0) }) else { throw MandateError.invalidAmount }
        let (integral, overflow) = whole.multipliedReportingOverflow(by: 1_000_000)
        let fractional = UInt64(fraction.padding(toLength: 6, withPad: "0", startingAt: 0)) ?? 0
        let (total, sumOverflow) = integral.addingReportingOverflow(fractional)
        guard !overflow, !sumOverflow, total > 0 else { throw MandateError.invalidAmount }
        units = total
    }
    public var display: String {
        let whole = units / 1_000_000
        let remainder = units % 1_000_000
        guard remainder != 0 else { return String(whole) }
        var fraction = String(format: "%06llu", remainder)
        while fraction.last == "0" { fraction.removeLast() }
        return "\(whole).\(fraction)"
    }
}

public enum MateService: UInt8, CaseIterable, Codable, Sendable {
    case translation = 0
    case summary = 1
    public var title: String { self == .translation ? "翻訳" : "要約" }
    public var bit: UInt8 { 1 << rawValue }
}

/// Secret input. This type is NEVER an HTTP request type.
public struct PrivatePolicy: Codable, Equatable, Sendable {
    public let budget: UInt64
    public let services: UInt8
    public let salt: Data
    public init(budget: UInt64, services: UInt8, salt: Data) throws {
        guard budget > 0, services > 0, services <= 3, salt.count == 32 else { throw MandateError.invalidPolicy }
        self.budget = budget; self.services = services; self.salt = salt
    }
    public func material() throws -> Data {
        guard budget > 0, services > 0, services <= 3, salt.count == 32 else { throw MandateError.invalidPolicy }
        return Data("ZKM-POL1".utf8) + CanonicalBytes.u64(budget) + Data([services]) + salt
    }
    public func check(spent: UInt64, amount: UInt64, service: MateService) throws {
        guard amount > 0 else { throw MandateError.invalidAmount }
        guard services & service.bit != 0 else { throw MandateError.serviceNotAllowed }
        guard spent <= budget, amount <= budget - spent else { throw MandateError.overBudget }
    }
}

public struct MandateGrant: Codable, Equatable, Sendable {
    public let owner: String
    public let agent: String
    public let policyHash: String
    public let validUntil: UInt64
    public let nonce: String
    public init(owner: String, agent: String, policyHash: String, validUntil: UInt64, nonce: String) throws {
        _ = try CanonicalBytes.hex(owner, count: 20); _ = try CanonicalBytes.hex(agent, count: 20)
        _ = try CanonicalBytes.hex(policyHash, count: 32)
        guard owner.lowercased() != agent.lowercased(), validUntil > 0, !nonce.isEmpty, nonce.utf8.allSatisfy({ (48...57).contains($0) }),
              nonce.count == 1 || nonce.first != "0",
              nonce.count < 78 || (nonce.count == 78 && nonce <= "115792089237316195423570985008687907853269984665640564039457584007913129639935") else { throw MandateError.invalidPolicy }
        self.owner = owner; self.agent = agent; self.policyHash = policyHash; self.validUntil = validUntil; self.nonce = nonce
    }
}

public struct MandateAction: Codable, Equatable, Sendable {
    public let mandateId: String
    public let recipient: String
    public let amount: String
    public let service: UInt8
    public let nonce: String
    public let expiresAt: UInt64
    public let requestHash: String
    public let spentBefore: String
    public init(mandateId: String, recipient: String, amount: UInt64, service: MateService, nonce: String,
                expiresAt: UInt64, requestHash: String, spentBefore: UInt64) {
        self.mandateId = mandateId; self.recipient = recipient; self.amount = String(amount)
        self.service = service.rawValue; self.nonce = nonce; self.expiresAt = expiresAt
        self.requestHash = requestHash; self.spentBefore = String(spentBefore)
    }
    public func context(chainID: UInt64, vault: String) throws -> Data {
        guard chainID > 0, expiresAt > 0, MateService(rawValue: service) != nil,
              let amountValue = UInt64(amount), amountValue > 0,
              UInt64(spentBefore) != nil else { throw MandateError.invalidAction }
        return try Data("ZKM-ACT1".utf8) + CanonicalBytes.u64(chainID)
            + CanonicalBytes.hex(vault, count: 20) + CanonicalBytes.hex(mandateId, count: 32)
            + CanonicalBytes.hex(recipient, count: 20) + CanonicalBytes.hex(nonce, count: 32)
            + CanonicalBytes.u64(expiresAt) + CanonicalBytes.hex(requestHash, count: 32)
    }
    public func material(chainID: UInt64, vault: String) throws -> Data {
        guard let spent = UInt64(spentBefore), let value = UInt64(amount) else { throw MandateError.invalidAction }
        return try context(chainID: chainID, vault: vault) + CanonicalBytes.u64(spent) + CanonicalBytes.u64(value) + Data([service])
    }
}

public enum SigningDocument {
    public static func grant(_ grant: MandateGrant, chainID: UInt64, vault: String) throws -> String {
        try encode(type: "Grant", fields: [
            ["name":"owner","type":"address"], ["name":"agent","type":"address"],
            ["name":"policyHash","type":"bytes32"], ["name":"validUntil","type":"uint64"], ["name":"nonce","type":"uint256"]
        ], message: ["owner":grant.owner,"agent":grant.agent,"policyHash":grant.policyHash,
                     "validUntil":String(grant.validUntil),"nonce":grant.nonce], chainID: chainID, vault: vault)
    }
    public static func execution(actionHash: String, chainID: UInt64, vault: String) throws -> String {
        _ = try CanonicalBytes.hex(actionHash, count: 32)
        return try encode(type: "Execution", fields: [["name":"actionHash","type":"bytes32"]],
                          message: ["actionHash":actionHash], chainID:chainID, vault:vault)
    }
    private static func encode(type: String, fields: [[String:String]], message: [String:String], chainID: UInt64, vault: String) throws -> String {
        _ = try CanonicalBytes.hex(vault, count: 20)
        guard chainID > 0 else { throw MandateError.invalidAction }
        let value: [String:Any] = [
            "domain": ["name":"ZeroKey Mate","version":"1","chainId":String(chainID),"verifyingContract":vault],
            "types": ["EIP712Domain": [["name":"name","type":"string"],["name":"version","type":"string"],
                       ["name":"chainId","type":"uint256"],["name":"verifyingContract","type":"address"]], type:fields],
            "primaryType":type,"message":message
        ]
        return String(decoding: try JSONSerialization.data(withJSONObject:value, options:[.sortedKeys]), as:UTF8.self)
    }
}
