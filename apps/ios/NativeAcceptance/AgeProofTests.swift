import XCTest
import Foundation
import MateAgeProof
import MateCore
@testable import ZeroKeyMate

final class AgeProofTests: XCTestCase {
    func testNativeKeccakAndCompleteOrderCommitment() throws {
        guard MateAgeNative.available else { throw XCTSkip("Build the real age runtime before native acceptance.") }
        XCTAssertEqual(try CanonicalBytes.hexString(MateAgeNative.keccak256(Data())),
                       "0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470")
        struct Reference: Decodable { let connection: AgeShopConnection, key: String, now: UInt64, order: AgeShopOrder }
        let bundle = Bundle(for: Self.self)
        let file = bundle.url(forResource: "shop-order", withExtension: "json")
            ?? bundle.url(forResource: "shop-order", withExtension: "json", subdirectory: "AgeFixtures")
        let ref = try JSONDecoder().decode(Reference.self, from: Data(contentsOf: XCTUnwrap(file)))
        try AgeShopProtocol.validate(ref.order, connection: ref.connection, payer: ref.order.payer,
                                    key: ref.key, now: ref.now, keccak: MateAgeNative.keccak256)
    }
    func testActualNativeAgeProofAndPrivateWitnessRejections() throws {
        guard MateAgeNative.available else { throw XCTSkip("Build the real age runtime before native acceptance.") }
        setenv("RAYON_NUM_THREADS", "2", 1)
        let prover = try XCTUnwrap(Bundle.main.url(forResource: "age", withExtension: "pkp"))
        let verifier = try XCTUnwrap(Bundle.main.url(forResource: "age", withExtension: "pkv"))
        let bundle = Bundle(for: Self.self)
        func input(_ name: String) throws -> Data {
            let file = bundle.url(forResource: name, withExtension: "json")
                ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "AgeFixtures")
            return try Data(contentsOf: XCTUnwrap(file))
        }
        let start = ContinuousClock.now
        let first = try MateAgeNative.prove(proverPath: prover.path, verifierPath: verifier.path, input: input("valid"))
        let elapsed = start.duration(to: .now)
        let second = try MateAgeNative.prove(proverPath: prover.path, verifierPath: verifier.path, input: input("valid"))
        XCTAssertEqual(first.proof.count, 384)
        XCTAssertEqual(first.publicInputs.count, 8)
        XCTAssertEqual(first.publicInputs, second.publicInputs)
        XCTAssertEqual(first.publicInputs[0], Data(repeating: 0, count: 16) + Data(repeating: 1, count: 16))
        XCTAssertNotEqual(first.proof.subdata(in: 256..<320), second.proof.subdata(in: 256..<320))
        for name in ["underage", "changed-order"] {
            XCTAssertThrowsError(try MateAgeNative.prove(proverPath: prover.path, verifierPath: verifier.path, input: input(name))) {
                XCTAssertEqual($0 as? MateAgeNativeError, .rejected(4))
            }
        }
        // Public timing/size evidence only. Never print the private input or a
        // captured assertion payload from the compiler/prover.
        print("Native age acceptance: synthetic only, 384 proof bytes, first proof \(elapsed)")
    }
}
