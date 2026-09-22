import Foundation
import CryptoSwift
import libsecp256k1

/// The fixed Arc USDC EIP-3009 domain. No model or merchant chooses a type,
/// target, domain, or hash. Private keys are never passed to this verifier.
public struct PaymentSignatureVerifier: ExternalPaymentSignatureVerifier {
    public init() {}

    public static func digest(_ approval: PaymentApproval) throws -> Data {
        try approval.validate(now: approval.createdAt)
        let a = approval.authorization
        let domain = try hash(hash(Data("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)".utf8))
            + hash(Data("USDC".utf8)) + hash(Data("2".utf8))
            + word(AgeShopProtocol.chainID) + address(AgeShopProtocol.token))
        let message = try hash(hash(Data("TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)".utf8))
            + address(a.from) + address(a.to) + integer(a.value) + integer(a.validAfter)
            + integer(a.validBefore) + CanonicalBytes.hex(a.nonce, count: 32))
        return hash(Data([0x19, 0x01]) + domain + message)
    }

    public func verify(_ signature: String, approval: PaymentApproval) throws {
        let bytes = try CanonicalBytes.hex(signature, count: 65)
        let recovery = bytes[64]
        guard recovery == 27 || recovery == 28 else { throw ExternalPaymentError.invalidAuthorization }
        // Circle/OpenZeppelin expect canonical low-s signatures. Do not silently
        // normalize a wallet response into different payment bytes.
        let halfOrder = try CanonicalBytes.hex("0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0", count: 32)
        let s = Data(bytes[32..<64])
        guard s.contains(where: { $0 != 0 }), !halfOrder.lexicographicallyPrecedes(s) else {
            throw ExternalPaymentError.invalidAuthorization
        }
        guard let context = secp256k1_context_create(UInt32(SECP256K1_CONTEXT_VERIFY)) else {
            throw ExternalPaymentError.invalidAuthorization
        }
        defer { secp256k1_context_destroy(context) }
        var recovered = secp256k1_ecdsa_recoverable_signature()
        var key = secp256k1_pubkey()
        let digest = try Self.digest(approval)
        let valid = bytes.withUnsafeBytes { raw in
            secp256k1_ecdsa_recoverable_signature_parse_compact(context, &recovered,
                raw.bindMemory(to: UInt8.self).baseAddress!, Int32(recovery - 27))
        }
        guard valid == 1, digest.withUnsafeBytes({ raw in
            secp256k1_ecdsa_recover(context, &key, &recovered, raw.bindMemory(to: UInt8.self).baseAddress!)
        }) == 1 else { throw ExternalPaymentError.invalidAuthorization }
        var publicKey = [UInt8](repeating: 0, count: 65), length = 65
        guard secp256k1_ec_pubkey_serialize(context, &publicKey, &length, &key,
            UInt32(SECP256K1_EC_UNCOMPRESSED)) == 1, length == 65, publicKey[0] == 4 else {
            throw ExternalPaymentError.invalidAuthorization
        }
        let payer = Data(Self.hash(Data(publicKey.dropFirst())).suffix(20))
        guard payer == (try CanonicalBytes.hex(approval.authorization.from, count: 20)) else {
            throw ExternalPaymentError.invalidAuthorization
        }
    }

    public static func hash(_ data: Data) -> Data { Data(SHA3(variant: .keccak256).calculate(for: Array(data))) }
    private static func word(_ value: UInt64) -> Data { Data(repeating: 0, count: 24) + CanonicalBytes.u64(value) }
    private static func integer(_ value: String) throws -> Data {
        guard let n = UInt64(value), String(n) == value else { throw ExternalPaymentError.invalidAuthorization }
        return word(n)
    }
    private static func address(_ value: String) throws -> Data {
        try Data(repeating: 0, count: 12) + CanonicalBytes.hex(value, count: 20)
    }
}
