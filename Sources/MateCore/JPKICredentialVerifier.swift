import Foundation
#if canImport(Security) && canImport(CryptoKit)
import Security
import CryptoKit

public enum JPKIVerificationError: Error, Equatable {
    case malformedCertificate, unsupportedBirthDate, untrustedCertificate, invalidCardSignature, invalidChallenge
}

/// Local cryptographic authentication only. Revocation has NOT been checked.
/// Not Codable: the date, certificate and card signature are private ZK inputs,
/// never the payload submitted to a merchant or published on a chain.
public struct JPKILocalCredential: Sendable {
    public let birthDate: UnverifiedCardBirthDate
    public let authentication: UnverifiedJPKIAuthentication
    public let revocationChecked = false
    fileprivate init(birthDate: UnverifiedCardBirthDate, authentication: UnverifiedJPKIAuthentication) {
        self.birthDate = birthDate; self.authentication = authentication
    }
}

public enum JPKICredentialVerifier {
    // J-LIS official SHA-256 fingerprints, checked on 2026-09-12. Roots from
    // the card, OS store, server, model, and caller are never trusted here.
    static let rootPins = [
        "signca02": "79679c33e4cc9319440f1ad120a597ff1844e2ef217063adb176966fd5e6fbeb",
        "signca03": "d227f6cde11d35c5252178f106f843d24651944975413b539fa2fb68dbfa365f"
    ]
    static func pinnedRoots() throws -> [Data] {
        try rootPins.sorted(by: { $0.key < $1.key }).map { name, fingerprint in
            guard let url = Bundle.module.url(forResource: name, withExtension: "cer", subdirectory: "JPKI"),
                  let data = try? Data(contentsOf: url),
                  SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == fingerprint else {
                throw JPKIVerificationError.untrustedCertificate
            }
            return data
        }
    }

    public static func verify(_ authentication: UnverifiedJPKIAuthentication, challenge: JPKIChallenge,
                              now: Date = Date()) throws -> JPKILocalCredential {
        try verify(authentication, challenge: challenge, now: now, roots: pinnedRoots())
    }

    /// Internal root injection is for synthetic cryptographic tests only. No
    /// external caller or runtime configuration can replace the public roots.
    static func verify(_ authentication: UnverifiedJPKIAuthentication, challenge: JPKIChallenge,
                       now: Date, roots: [Data]) throws -> JPKILocalCredential {
        let date = try verifyCertificate(authentication.certificate, now: now, roots: roots)
        guard let certificate = SecCertificateCreateWithData(nil, authentication.certificate as CFData),
              let key = SecCertificateCopyKey(certificate), authentication.signature.count == 256,
              SecKeyVerifySignature(key, .rsaSignatureMessagePKCS1v15SHA256, challenge.message as CFData,
                                    authentication.signature as CFData, nil) else {
            throw JPKIVerificationError.invalidCardSignature
        }
        return JPKILocalCredential(birthDate: date, authentication: authentication)
    }

    public static func verifyCertificate(_ der: Data, now: Date = Date()) throws -> UnverifiedCardBirthDate {
        try verifyCertificate(der, now: now, roots: pinnedRoots())
    }

    static func verifyCertificate(_ der: Data, now: Date, roots: [Data]) throws -> UnverifiedCardBirthDate {
        let fields = try JPKICertificateFields(der)
        guard let certificate = SecCertificateCreateWithData(nil, der as CFData), !roots.isEmpty,
              let key = SecCertificateCopyKey(certificate), SecKeyGetBlockSize(key) == 256,
              SecKeyIsAlgorithmSupported(key, .verify, .rsaSignatureMessagePKCS1v15SHA256) else {
            throw JPKIVerificationError.untrustedCertificate
        }
        let anchors = roots.compactMap { SecCertificateCreateWithData(nil, $0 as CFData) }
        guard anchors.count == roots.count else { throw JPKIVerificationError.untrustedCertificate }
        var trust: SecTrust?
        guard SecTrustCreateWithCertificates([certificate] as CFArray, SecPolicyCreateBasicX509(), &trust) == errSecSuccess,
              let trust,
              SecTrustSetAnchorCertificates(trust, anchors as CFArray) == errSecSuccess,
              SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess,
              SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess,
              SecTrustSetVerifyDate(trust, now as CFDate) == errSecSuccess,
              SecTrustEvaluateWithError(trust, nil),
              // This profile is issued directly by a J-LIS signing root. An
              // injected intermediate or a trusted root used as a leaf fails.
              SecTrustGetCertificateCount(trust) == 2 else {
            throw JPKIVerificationError.untrustedCertificate
        }
        return fields.birthDate
    }
}

/// Minimal, bounded DER traversal for the DOB in the *signed TBS extensions*.
/// It never scans arbitrary bytes for an OID/date and rejects duplicate fields.
/// Full X.509 signature, validity, constraints and critical-extension handling
/// remain Security.framework's responsibility, with networking disabled.
struct JPKICertificateFields {
    let birthDate: UnverifiedCardBirthDate
    init(_ der: Data) throws {
        guard (260...8192).contains(der.count) else { throw JPKIVerificationError.malformedCertificate }
        let certificate = try DERNode.single(der, tag: 0x30).children()
        guard certificate.count == 3, certificate[0].tag == 0x30, certificate[1].tag == 0x30,
              certificate[2].tag == 0x03 else { throw JPKIVerificationError.malformedCertificate }
        let sha256RSA = Data([0x06,0x09,0x2A,0x86,0x48,0x86,0xF7,0x0D,0x01,0x01,0x0B,0x05,0x00])
        let tbs = try certificate[0].children()
        guard certificate[1].value == sha256RSA, tbs.count == 8,
              tbs[0].tag == 0xA0, tbs[0].value == Data([0x02,0x01,0x02]),
              tbs[1].tag == 0x02, tbs[2].tag == 0x30, tbs[2].value == sha256RSA,
              tbs[3].tag == 0x30, tbs[4].tag == 0x30, tbs[5].tag == 0x30,
              tbs[6].tag == 0x30, tbs[7].tag == 0xA3 else { throw JPKIVerificationError.malformedCertificate }
        let extensions = try DERNode.single(tbs[7].value, tag: 0x30).children()
        var seen = Set<Data>(), san: Data?, usage: Data?
        for item in extensions {
            guard item.tag == 0x30 else { throw JPKIVerificationError.malformedCertificate }
            let parts = try item.children()
            guard (2...3).contains(parts.count), parts[0].tag == 6,
                  seen.insert(parts[0].value).inserted, parts.last?.tag == 4 else {
                throw JPKIVerificationError.malformedCertificate
            }
            if parts.count == 3 {
                guard parts[1].tag == 1, parts[1].value == Data([0xFF]) else { throw JPKIVerificationError.malformedCertificate }
            }
            if parts[0].value == Data([0x55,0x1D,0x11]) { san = parts.last!.value }
            if parts[0].value == Data([0x55,0x1D,0x0F]) {
                guard parts.count == 3 else { throw JPKIVerificationError.malformedCertificate }
                usage = parts.last!.value
            }
        }
        guard let san, usage == Data([0x03,0x02,0x06,0xC0]) else { throw JPKIVerificationError.malformedCertificate }
        let names = try DERNode.single(san, tag: 0x30).children()
        // 1.2.392.200149.8.5.5.4: J-LIS profile 3.2, physical signing cert.
        let dobOID = Data([0x2A,0x83,0x08,0x8C,0x9B,0x55,0x08,0x05,0x05,0x04])
        var date: UnverifiedCardBirthDate?
        for name in names where name.tag == 0xA0 {
            let other = try name.children()
            guard other.count == 2, other[0].tag == 6, other[1].tag == 0xA0 else {
                throw JPKIVerificationError.malformedCertificate
            }
            if other[0].value == dobOID {
                guard date == nil else { throw JPKIVerificationError.malformedCertificate }
                let value = try DERNode.single(other[1].value, tag: 0x0C).value
                // EYYYYMMDD. Unknown/seasonal/partial dates are never guessed.
                guard value.count == 9, let era = value.first, (48...53).contains(era) else {
                    throw JPKIVerificationError.unsupportedBirthDate
                }
                do { date = try UnverifiedCardBirthDate(ascii: Data(value.dropFirst())) }
                catch { throw JPKIVerificationError.unsupportedBirthDate }
            }
        }
        guard let date else { throw JPKIVerificationError.unsupportedBirthDate }
        birthDate = date
    }
}

struct DERNode {
    let tag: UInt8
    let value: Data
    static func single(_ data: Data, tag: UInt8) throws -> DERNode {
        let nodes = try parse(data)
        guard nodes.count == 1, nodes[0].tag == tag else { throw JPKIVerificationError.malformedCertificate }
        return nodes[0]
    }
    func children() throws -> [DERNode] { try Self.parse(value) }
    static func parse(_ data: Data) throws -> [DERNode] {
        let bytes = Array(data)
        guard bytes.count <= 8192 else { throw JPKIVerificationError.malformedCertificate }
        var result: [DERNode] = [], offset = 0
        while offset < bytes.count {
            guard offset + 2 <= bytes.count, result.count < 64 else { throw JPKIVerificationError.malformedCertificate }
            let tag = bytes[offset], firstLength = bytes[offset + 1]
            guard tag & 0x1F != 0x1F else { throw JPKIVerificationError.malformedCertificate }
            offset += 2
            var length = Int(firstLength)
            if firstLength & 0x80 != 0 {
                let count = Int(firstLength & 0x7F)
                guard (1...2).contains(count), offset + count <= bytes.count, bytes[offset] != 0 else {
                    throw JPKIVerificationError.malformedCertificate
                }
                length = 0
                for _ in 0..<count { length = length * 256 + Int(bytes[offset]); offset += 1 }
                guard length >= 128, count == 1 || length >= 256 else { throw JPKIVerificationError.malformedCertificate }
            }
            guard length <= bytes.count - offset else { throw JPKIVerificationError.malformedCertificate }
            result.append(DERNode(tag: tag, value: Data(bytes[offset..<(offset + length)])))
            offset += length
        }
        return result
    }
}
#endif
