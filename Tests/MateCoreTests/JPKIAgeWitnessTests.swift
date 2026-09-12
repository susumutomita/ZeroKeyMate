import XCTest
@testable import MateCore
#if canImport(Security) && canImport(CryptoKit)
import CryptoKit

final class JPKIAgeWitnessTests: XCTestCase {
    private func fixture(_ name: String, ext: String = "der") throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "JPKI")))
    }
    private func prepare(order: UInt8 = 1, nonce: UInt8 = 2, start: UInt64 = 1_800_000_000,
                         end: UInt64 = 1_800_000_900, now: Double = 1_800_000_100,
                         card: String = "card", trusted: Bool = true) throws -> JPKIAgeWitness {
        let authentication = try UnverifiedJPKIAuthentication(certificate: fixture(card), signature: fixture("card-signature", ext: "bin"))
        if trusted {
            return try JPKIAgeWitness.prepare(authentication: authentication,
                orderHash: Data(repeating: order, count: 32), nonce: Data(repeating: nonce, count: 32),
                referenceTime: start, expiresAt: end, now: Date(timeIntervalSince1970: now), roots: [fixture("root")])
        }
        return try JPKIAgeWitness.prepare(authentication: authentication,
            orderHash: Data(repeating: order, count: 32), nonce: Data(repeating: nonce, count: 32),
            referenceTime: start, expiresAt: end, now: Date(timeIntervalSince1970: now))
    }
    private func hash(_ bytes: [UInt8]) -> String {
        SHA256.hash(data: Data(bytes)).map { String(format: "%02x", $0) }.joined()
    }
    func testPrivateWitnessMatchesIndependentPythonCryptographyReference() throws {
        // The reference contains only hashes derived from repository fake certs.
        let reference = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("age-witness-reference", ext: "json")) as? [String: Any])
        let witness = try prepare()
        XCTAssertEqual(witness.publicInputs, reference["publicInputs"] as? [String])
        XCTAssertEqual(witness.rootKeyHash.map { String(format: "%02x", $0) }.joined(), reference["rootHash"] as? String)
        try witness.withLocalProverInput { input in
            let values = try XCTUnwrap(JSONSerialization.jsonObject(with: input) as? [String: Any])
            let tbs = try XCTUnwrap(values["tbs"] as? [UInt8])
            let length = try XCTUnwrap(values["tbs_length"] as? Int)
            XCTAssertEqual(tbs.count, 2048)
            XCTAssertEqual(length, reference["tbsLength"] as? Int)
            XCTAssertEqual(hash(Array(tbs.prefix(length))), reference["tbsHash"] as? String)
            XCTAssertTrue(tbs.dropFirst(length).allSatisfy { $0 == 0 })
            XCTAssertEqual(hash(try XCTUnwrap(values["root_redc"] as? [UInt8])), reference["rootRedcHash"] as? String)
            XCTAssertEqual(hash(try XCTUnwrap(values["card_redc"] as? [UInt8])), reference["cardRedcHash"] as? String)
            XCTAssertEqual(try XCTUnwrap(values["card_signature"] as? [UInt8]), Array(try fixture("card-signature", ext: "bin")))
            XCTAssertNil(values["birthDate"]); XCTAssertNil(values["pin"])
        }
        XCTAssertEqual(String(reflecting: witness), "JPKIAgeWitness(private input redacted)")
    }
    func testPublicEntryRejectsFakeIssuerAndChallengeReplay() {
        XCTAssertThrowsError(try prepare(trusted: false))
        XCTAssertThrowsError(try prepare(order: 3))
        XCTAssertThrowsError(try prepare(nonce: 4))
        XCTAssertThrowsError(try prepare(order: 0))
        XCTAssertThrowsError(try prepare(card: "unknown-date"))
        XCTAssertThrowsError(try prepare(card: "duplicate-date"))
    }
    func testOrderWindowRejectsExpiryFutureOverflowAndWrongDuration() {
        for args: (UInt64, UInt64, Double) in [
            (1_800_000_000, 1_800_000_900, 1_800_000_900),
            (1_800_000_000, 1_800_000_900, 1_799_999_999),
            (1_800_000_000, 1_800_000_901, 1_800_000_100),
            (1_800_000_000, 1_800_000_000, 1_800_000_100),
            (.max, 0, 1_800_000_100), (0, .max, .infinity),
        ] {
            XCTAssertThrowsError(try prepare(start: args.0, end: args.1, now: args.2)) {
                XCTAssertEqual($0 as? JPKIAgeWitnessError, .invalidOrderWindow)
            }
        }
    }
    func testU128PackingPreservesHighBitAndLeadingZeros() {
        XCTAssertEqual(JPKIAgeWitness.decimal128(Array(repeating: 0, count: 16)), "0")
        XCTAssertEqual(JPKIAgeWitness.decimal128(Array(repeating: 255, count: 16)), "340282366920938463463374607431768211455")
        XCTAssertEqual(JPKIAgeWitness.decimal128([128] + Array(repeating: 0, count: 15)), "170141183460469231731687303715884105728")
        XCTAssertEqual(JPKIAgeWitness.decimal128(Array(repeating: 0, count: 15) + [1]), "1")
    }
    func testMalformedReductionModuliAreRejectedBeforeDivision() {
        for modulus in [[UInt8](), Array(repeating: UInt8(0), count: 256), Array(repeating: UInt8(128), count: 256)] {
            XCTAssertThrowsError(try JPKIAgeWitness.reductionHint(modulus))
        }
    }
}
#endif
