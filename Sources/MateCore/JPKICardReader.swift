import Foundation
#if canImport(CryptoKit)
import CryptoKit

/// APDU identifiers adapted from jpki/myna (MIT), revision
/// 12f015240c4980d704e5bf2f6cd2f0e4ae4045b9, src/jpki.rs and reader.rs.
/// No logging, PIN retry, persistence or networking is performed here.
public enum JPKICardReader {
    public static let applicationID = Data([0xD3, 0x92, 0xF0, 0x00, 0x26, 0x01, 0x00, 0x00, 0x01])

    public static func validSigningPIN(_ pin: String) -> Bool {
        let bytes = Array(pin.utf8)
        return (6...16).contains(bytes.count) && bytes.allSatisfy { (48...57).contains($0) || (65...90).contains($0) }
            && bytes.contains { (48...57).contains($0) } && bytes.contains { (65...90).contains($0) }
    }

    /// A caller must present the order and obtain explicit card/PIN interaction.
    /// The result is untrusted until certificate AND challenge verification pass.
    @MainActor public static func authenticate(pin: String, challenge: JPKIChallenge,
        send: (MyNumberCardCommand) async throws -> MyNumberCardResponse) async throws -> UnverifiedJPKIAuthentication {
        guard validSigningPIN(pin) else { throw MyNumberCardError.invalidPIN }
        func exchange(_ command: MyNumberCardCommand) async throws -> Data {
            try Task.checkCancellation()
            let response = try await send(command)
            try Task.checkCancellation()
            guard response.sw1 == 0x90 && response.sw2 == 0 else {
                if command.instruction == 0x20 {
                    if response.sw1 == 0x69 && response.sw2 == 0x83 { throw MyNumberCardError.pinBlocked }
                    if response.sw1 == 0x63 && response.sw2 & 0xF0 == 0xC0 {
                        let count = Int(response.sw2 & 0x0F)
                        if count == 0 { throw MyNumberCardError.pinBlocked }
                        throw MyNumberCardError.pinRejected(remainingAttempts: count)
                    }
                }
                throw MyNumberCardError.commandRejected
            }
            return response.data
        }
        func select(_ id: UInt8) async throws {
            _ = try await exchange(.init(instruction: 0xA4, p1: 2, p2: 0x0C, data: Data([0, id])))
        }
        _ = try await exchange(.init(instruction: 0xA4, p1: 4, p2: 0x0C, data: applicationID))
        try await select(0x1B)
        _ = try await exchange(.init(instruction: 0x20, p1: 0, p2: 0x80, data: Data(pin.utf8)))
        try await select(0x01)
        // Read the outer DER header first; cap length before any allocation or
        // further APDU. No accepting a certificate truncated at the first page.
        let header = try await exchange(.init(instruction: 0xB0, p1: 0, p2: 0, responseLength: 4))
        guard header.count == 4, header[0] == 0x30, header[1] == 0x82 else {
            throw MyNumberCardError.malformedResponse
        }
        let size = Int(header[2]) * 256 + Int(header[3]) + 4
        guard (260...8192).contains(size) else { throw MyNumberCardError.malformedResponse }
        var certificate = header
        while certificate.count < size {
            let offset = certificate.count, count = min(256, size - offset)
            let page = try await exchange(.init(instruction: 0xB0, p1: UInt8(offset >> 8), p2: UInt8(offset & 255), responseLength: count))
            guard page.count == count else { throw MyNumberCardError.malformedResponse }
            certificate.append(page)
        }
        // Validate the signed credential before asking the card to sign. This
        // does not establish revocation status or grant shop authorization.
        _ = try JPKICredentialVerifier.verifyCertificate(certificate)
        try await select(0x1A)
        let digestInfo = Data([0x30,0x31,0x30,0x0D,0x06,0x09,0x60,0x86,0x48,0x01,0x65,0x03,0x04,0x02,0x01,0x05,0x00,0x04,0x20])
            + Data(SHA256.hash(data: challenge.message))
        let signature = try await exchange(.init(instructionClass: 0x80, instruction: 0x2A, p1: 0, p2: 0x80, data: digestInfo, responseLength: 256))
        guard signature.count == 256 else { throw MyNumberCardError.malformedResponse }
        return UnverifiedJPKIAuthentication(certificate: certificate, signature: signature)
    }
}

public struct JPKIChallenge: Sendable {
    public let message: Data
    /// Both fields must be generated/bound by Mate, never a model-produced URL
    /// or arbitrary signing message. orderHash commits to all checkout terms.
    public init(orderHash: Data, nonce: Data) throws {
        guard orderHash.count == 32, nonce.count == 32,
              orderHash.contains(where: { $0 != 0 }), nonce.contains(where: { $0 != 0 }) else {
            throw JPKIVerificationError.invalidChallenge
        }
        message = Data("ZeroKeyMate age authentication v1\0".utf8) + orderHash + nonce
    }
}

/// Contains personal data. Intentionally not Codable; keep only in memory for
/// local proving. Never send either field to the shop, an LLM, or logs.
public struct UnverifiedJPKIAuthentication: Sendable {
    public let certificate: Data
    public let signature: Data
    public init(certificate: Data, signature: Data) { self.certificate = certificate; self.signature = signature }
}
#endif
