import Foundation
#if canImport(Security) && canImport(CryptoKit)
import Security
import CryptoKit

public enum JPKIAgeWitnessError: Error, Equatable {
    case invalidOrderWindow, unsupportedCertificate, unsupportedKey
}

/// In-memory input to the LOCAL age prover. This is not a merchant payload or
/// an age approval. Do not persist, log, send to a model or transmit this value.
/// No Codable conformance; diagnostics deliberately redact the private input.
public struct JPKIAgeWitness: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let rootKeyHash: Data
    public let publicInputs: [String]
    private let tbs: [UInt8]
    private let tbsLength: Int
    private let certificateSignature: [UInt8]
    private let rootModulus: [UInt8]
    private let rootRedc: [UInt8]
    private let cardRedc: [UInt8]
    private let cardSignature: [UInt8]
    public var description: String { "JPKIAgeWitness(private input redacted)" }
    public var debugDescription: String { description }

    /// This scope exists for the native prover bridge, which consumes JSON in
    /// memory. It performs no file, card, network or wallet operation. Swift/Data
    /// copies can outlive this buffer; this is not a guarantee of secure erasure.
    public func withLocalProverInput<Result>(_ consume: (Data) throws -> Result) throws -> Result {
        let names = ["order_high", "order_low", "nonce_high", "nonce_low", "root_high", "root_low", "reference_time", "expires_at"]
        var values: [String: Any] = Dictionary(uniqueKeysWithValues: zip(names, publicInputs.map { $0 as Any }))
        values["tbs"] = tbs; values["tbs_length"] = tbsLength
        values["certificate_signature"] = certificateSignature
        values["root_modulus"] = rootModulus; values["root_redc"] = rootRedc
        values["card_redc"] = cardRedc; values["card_signature"] = cardSignature
        var input = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
        defer { input.resetBytes(in: 0..<input.count) }
        return try consume(input)
    }

    public static func prepare(authentication: UnverifiedJPKIAuthentication, orderHash: Data, nonce: Data,
                               referenceTime: UInt64, expiresAt: UInt64, now: Date = Date()) throws -> Self {
        try prepare(authentication: authentication, orderHash: orderHash, nonce: nonce,
                    referenceTime: referenceTime, expiresAt: expiresAt, now: now,
                    roots: JPKICredentialVerifier.pinnedRoots())
    }

    // Synthetic root injection is internal to the test target. Product callers
    // cannot configure or substitute an issuer's trust root.
    static func prepare(authentication: UnverifiedJPKIAuthentication, orderHash: Data, nonce: Data,
                        referenceTime: UInt64, expiresAt: UInt64, now: Date, roots: [Data]) throws -> Self {
        guard referenceTime >= 1_704_067_200, referenceTime <= 4_102_444_800,
              expiresAt > referenceTime, expiresAt - referenceTime == 900,
              now.timeIntervalSince1970.isFinite,
              Double(referenceTime) <= now.timeIntervalSince1970,
              now.timeIntervalSince1970 < Double(expiresAt) else { throw JPKIAgeWitnessError.invalidOrderWindow }
        let challenge = try JPKIChallenge(orderHash: orderHash, nonce: nonce)
        // Recheck both ends of the shop's window. A certificate valid at card
        // contact but expiring before checkout must not enter a proof attempt.
        _ = try JPKICredentialVerifier.verify(authentication, challenge: challenge,
                    now: Date(timeIntervalSince1970: Double(referenceTime)), roots: roots)
        _ = try JPKICredentialVerifier.verifyCertificate(authentication.certificate,
                    now: Date(timeIntervalSince1970: Double(expiresAt)), roots: roots)
        let cert = try DERNode.single(authentication.certificate, tag: 0x30).children()
        let tbs = cert[0].encoded
        guard tbs.count <= 2048, cert[2].value.count == 257, cert[2].value.first == 0 else {
            throw JPKIAgeWitnessError.unsupportedCertificate
        }
        let signature = Data(cert[2].value.dropFirst())
        var issuerModulus: [UInt8]?
        for root in roots {
            guard let certificate = SecCertificateCreateWithData(nil, root as CFData),
                  let key = SecCertificateCopyKey(certificate),
                  SecKeyVerifySignature(key, .rsaSignatureMessagePKCS1v15SHA256, tbs as CFData,
                                        signature as CFData, nil) else { continue }
            issuerModulus = try modulus(key)
            break
        }
        guard let issuerModulus,
              let certificate = SecCertificateCreateWithData(nil, authentication.certificate as CFData),
              let key = SecCertificateCopyKey(certificate) else { throw JPKIVerificationError.untrustedCertificate }
        let cardModulus = try modulus(key)
        let rootHash = Data(SHA256.hash(data: Data(issuerModulus)))
        let publicInputs = [orderHash, nonce, rootHash].flatMap {
            [decimal128(Array($0.prefix(16))), decimal128(Array($0.suffix(16)))]
        } + [String(referenceTime), String(expiresAt)]
        return Self(rootKeyHash: rootHash, publicInputs: publicInputs,
                    tbs: Array(tbs) + Array(repeating: 0, count: 2048 - tbs.count), tbsLength: tbs.count,
                    certificateSignature: Array(signature), rootModulus: issuerModulus,
                    rootRedc: try reductionHint(issuerModulus), cardRedc: try reductionHint(cardModulus),
                    cardSignature: Array(authentication.signature))
    }

    private static func modulus(_ key: SecKey) throws -> [UInt8] {
        guard SecKeyGetBlockSize(key) == 256,
              let data = SecKeyCopyExternalRepresentation(key, nil) as Data? else { throw JPKIAgeWitnessError.unsupportedKey }
        let parts = try DERNode.single(data, tag: 0x30).children()
        guard parts.count == 2, parts[0].tag == 2, parts[0].value.count == 257,
              parts[0].value.first == 0, parts[0].value.dropFirst().first! >= 128,
              parts[1].tag == 2, parts[1].value == Data([1, 0, 1]),
              parts[0].value.last! & 1 == 1 else { throw JPKIAgeWitnessError.unsupportedKey }
        return Array(parts[0].value.dropFirst())
    }

    // noir-bignum's bounded REDC hint: floor(2^4102 / RSA modulus). The circuit
    // constrains its correctness. This local long division uses no private key.
    static func reductionHint(_ modulus: [UInt8]) throws -> [UInt8] {
        guard modulus.count == 256, modulus[0] >= 128, modulus[255] & 1 == 1 else {
            throw JPKIAgeWitnessError.unsupportedKey
        }
        let divisor = [UInt8(0)] + modulus
        var remainder = [UInt8](repeating: 0, count: 257)
        var quotient = [UInt8](repeating: 0, count: 257)
        for bit in stride(from: 4102, through: 0, by: -1) {
            var carry: UInt16 = bit == 4102 ? 1 : 0
            for i in stride(from: 256, through: 0, by: -1) {
                let value = UInt16(remainder[i]) * 2 + carry
                remainder[i] = UInt8(value & 255); carry = value >> 8
            }
            if !remainder.lexicographicallyPrecedes(divisor) {
                var borrow = 0
                for i in stride(from: 256, through: 0, by: -1) {
                    let difference = Int(remainder[i]) - Int(divisor[i]) - borrow
                    remainder[i] = UInt8((difference + 256) & 255)
                    borrow = difference < 0 ? 1 : 0
                }
                guard bit < 2056 else { throw JPKIAgeWitnessError.unsupportedKey }
                quotient[256 - bit / 8] |= UInt8(1 << (bit % 8))
            }
        }
        return quotient
    }

    static func decimal128(_ bytes: [UInt8]) -> String {
        precondition(bytes.count == 16)
        var digits = [UInt16(0)] // least-significant decimal digit first
        for byte in bytes {
            var carry = UInt16(byte)
            for i in digits.indices {
                let value = digits[i] * 256 + carry
                digits[i] = value % 10; carry = value / 10
            }
            while carry > 0 { digits.append(carry % 10); carry /= 10 }
        }
        return digits.reversed().map(String.init).joined()
    }
}
#endif
