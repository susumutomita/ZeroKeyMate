import CryptoKit
import Foundation
import XCTest
import MateCore
import Verity
@testable import ZeroKeyMate

final class NativeProofTests: XCTestCase {
    func testNativeProveKitProvesAndVerifiesTheActualMandateCircuit() async throws {
        let policy=try PrivatePolicy(budget:5_000_000,services:3,salt:Data(0..<32))
        let action=MandateAction(mandateId:"0x"+String(repeating:"22",count:32),
            recipient:"0x"+String(repeating:"33",count:20),amount:3_000_000,service:.translation,
            nonce:"0x"+String(repeating:"44",count:32),expiresAt:2_000_000_000,
            requestHash:LocalSecrets.hash(Data("Hello, Mate.".utf8)),spentBefore:0)
        let proof=try await ProofService().prove(policy:policy,action:action,chainID:11_155_111,
                                                 vault:"0x"+String(repeating:"11",count:20))
        XCTAssertEqual(proof.policyHash,"0xd4582b4b691950b3bbd42b7109247f83f4bef912c028899b0e8a9260d1a0c3a9")
        XCTAssertEqual(proof.actionHash,"0x5c094c8e46c56b6dc6f364709b55912a3551ef3edaa548ea5cc34b4609f2961e")
        XCTAssertGreaterThan(proof.bytes.count,0)
        XCTAssertGreaterThanOrEqual(proof.elapsedMilliseconds,0)
        let keyURL=try XCTUnwrap(Bundle.main.url(forResource:"mate_policy",withExtension:"pkv"))
        let runtime=try Verity(backend:.provekit)
        let verifier=try runtime.loadVerifier(data:Data(contentsOf:keyURL))
        defer{verifier.close()}
        XCTAssertTrue(try verifier.verify(proof:Proof(data:proof.bytes)))
        var changed=proof.bytes
        changed[changed.count/2] ^= 1
        var rejected=false
        do {rejected = try !verifier.verify(proof:Proof(data:changed))} catch {rejected=true}
        XCTAssertTrue(rejected,"A tampered native proof must be rejected")
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("mate-native-evidence",isDirectory:true)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        try proof.bytes.write(to:directory.appendingPathComponent("native-proof.np"))
        print("NATIVE_PROOF_EVIDENCE bytes=\(proof.bytes.count) milliseconds=\(proof.elapsedMilliseconds) sha256=\(proof.proofHash)")
    }

    func testPrivatePolicyNeverAppearsInGrantSigningDocument() throws {
        let policy=try PrivatePolicy(budget:4_321_987,services:1,salt:Data(repeating:23,count:32))
        let grant=try MandateGrant(owner:"0x"+String(repeating:"11",count:20),agent:"0x"+String(repeating:"22",count:20),
            policyHash:LocalSecrets.hash(policy.material()),validUntil:2_000_000_000,nonce:"0")
        let json=try SigningDocument.grant(grant,chainID:11_155_111,vault:"0x"+String(repeating:"33",count:20))
        XCTAssertFalse(json.contains("4321987"))
        XCTAssertFalse(json.contains("budget"))
        XCTAssertFalse(json.contains("salt"))
        XCTAssertFalse(json.contains("services"))
    }
}
