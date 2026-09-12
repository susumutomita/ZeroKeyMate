import CryptoKit
import Foundation
import MateCore
import MateAgeProof

/// Only these two PUBLIC values may be submitted to the shop's /age route.
struct VerifiedAgeProof: Sendable, Encodable {
    let proof: String
    let rootKeyHash: String
}

/// Separate from spending-policy proofs. The card credential and witness stay
/// within this background actor; networking and signing are outside its scope.
actor AgeProofService {
    private var verifiedResources: (URL, URL)?

    func prepare() throws {
        try Task.checkCancellation()
        guard MateAgeNative.available else {
            throw ProductError.unavailable("On-device age verification is not installed yet.")
        }
        if verifiedResources != nil { return }
        guard let prover = Bundle.main.url(forResource: "age", withExtension: "pkp"),
              let verifier = Bundle.main.url(forResource: "age", withExtension: "pkv") else {
            throw ProductError.unavailable("The age verification resources are not installed yet.")
        }
        guard try hashFile(prover) == AgeProofPins.proverSHA256,
              try hashFile(verifier) == AgeProofPins.verifierSHA256 else { throw ProductError.invalidResponse }
        verifiedResources = (prover, verifier)
    }

    func prove(authentication: UnverifiedJPKIAuthentication, orderHash: Data, nonce: Data,
               referenceTime: UInt64, expiresAt: UInt64) throws -> VerifiedAgeProof {
        try prepare()
        let witness = try JPKIAgeWitness.prepare(authentication: authentication, orderHash: orderHash, nonce: nonce,
                                                referenceTime: referenceTime, expiresAt: expiresAt)
        guard let resources = verifiedResources else { throw ProductError.invalidResponse }
        try Task.checkCancellation()
        let result = try witness.withLocalProverInput { input in
            try MateAgeNative.prove(proverPath: resources.0.path, verifierPath: resources.1.path, input: input)
        }
        // The native call cannot yet be interrupted halfway through. Cancelling
        // always discards its result and must never start checkout afterward.
        try Task.checkCancellation()
        guard Date().timeIntervalSince1970 < Double(expiresAt), result.proof.count == 384,
              result.publicInputs.map(Self.decimal) == witness.publicInputs else { throw ProductError.invalidResponse }
        return VerifiedAgeProof(proof: Self.hex(result.proof), rootKeyHash: Self.hex(witness.rootKeyHash))
    }

    private func hashFile(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        // A full Data copy of the large public proving key would increase peak
        // memory before the prover even starts. Hash fixed-size chunks instead.
        while let chunk = try file.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty {
            try Task.checkCancellation(); hash.update(data: chunk)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private static func hex(_ bytes: Data) -> String {
        "0x" + bytes.map { String(format: "%02x", $0) }.joined()
    }
    private static func decimal(_ bytes: Data) -> String {
        var digits = [UInt16(0)]
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
