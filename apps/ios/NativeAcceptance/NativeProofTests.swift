import CryptoKit
import Foundation
import XCTest
import MateCore
import Verity
@testable import ZeroKeyMate

final class NativeProofTests: XCTestCase {
    func testNativeProveKitProvesAndVerifiesTheActualMandateCircuit() async throws {
        try XCTSkipUnless(Verity.runtimeMode == .native,"Native ProveKit is explicitly unavailable in a source-only build.")
        let policy=try PrivatePolicy(budget:5_000_000,services:3,salt:Data(0..<32))
        let action=MandateAction(mandateId:"0x"+String(repeating:"22",count:32),
            recipient:"0x"+String(repeating:"33",count:20),amount:3_000_000,service:.translation,
            nonce:"0x"+String(repeating:"44",count:32),expiresAt:2_000_000_000,
            requestHash:LocalSecrets.hash(Data("Hello, Mate.".utf8)),spentBefore:0)
        let service = ProofService()
        let proof=try await service.prove(policy:policy,action:action,chainID:11_155_111,
                                                 vault:"0x"+String(repeating:"11",count:20))
        XCTAssertEqual(proof.policyHash,"0xd4582b4b691950b3bbd42b7109247f83f4bef912c028899b0e8a9260d1a0c3a9")
        XCTAssertEqual(proof.actionHash,"0x5c094c8e46c56b6dc6f364709b55912a3551ef3edaa548ea5cc34b4609f2961e")
        XCTAssertGreaterThan(proof.bytes.count,0)
        XCTAssertGreaterThanOrEqual(proof.elapsedMilliseconds,0)
        XCTAssertFalse(proof.usedCachedKeys)
        XCTAssertGreaterThanOrEqual(proof.preparationMilliseconds,0)
        XCTAssertGreaterThanOrEqual(proof.totalMilliseconds,proof.elapsedMilliseconds)
        XCTAssertLessThanOrEqual(abs(proof.totalMilliseconds - proof.preparationMilliseconds - proof.elapsedMilliseconds),1)
        XCTAssertTrue(["Nominal","Fair","Serious","Critical","Unknown"].contains(proof.thermalStateBefore))
        XCTAssertTrue(["Nominal","Fair","Serious","Critical","Unknown"].contains(proof.thermalStateAfter))
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
        let exerciseRejected = try await ProofService().rejectsTamperedCopy(of: proof)
        XCTAssertTrue(exerciseRejected)
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("mate-native-evidence",isDirectory:true)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let file=directory.appendingPathComponent("native-proof.np")
        try proof.bytes.write(to:file)
        let attachment=XCTAttachment(contentsOfFile:file)
        attachment.name="native-proof.np";attachment.lifetime = .keepAlways
        add(attachment)
        let metrics:[String:Any]=["bytes":proof.bytes.count,"milliseconds":proof.elapsedMilliseconds,"sha256":proof.proofHash,
            "preparationMilliseconds":proof.preparationMilliseconds,"totalMilliseconds":proof.totalMilliseconds,
            "usedCachedKeys":proof.usedCachedKeys,"thermalStateBefore":proof.thermalStateBefore,
            "thermalStateAfter":proof.thermalStateAfter,"peakMemory":"not-measured"]
        let metricsAttachment=XCTAttachment(data:try JSONSerialization.data(withJSONObject:metrics,options:[.sortedKeys]),uniformTypeIdentifier:"public.json")
        metricsAttachment.name="native-proof-metrics.json";metricsAttachment.lifetime = .keepAlways
        add(metricsAttachment)
        // Same actor: subsequent requests must identify the actual cached-key path.
        var repeatedMetrics: [[String: Any]] = []
        for run in 1...3 {
            let repeated = try await service.prove(policy: policy, action: action, chainID: 11_155_111,
                vault: "0x" + String(repeating: "11", count: 20))
            XCTAssertTrue(repeated.usedCachedKeys)
            XCTAssertGreaterThanOrEqual(repeated.totalMilliseconds, repeated.elapsedMilliseconds)
            XCTAssertLessThanOrEqual(abs(repeated.totalMilliseconds - repeated.preparationMilliseconds - repeated.elapsedMilliseconds), 1)
            repeatedMetrics.append(["run":run, "milliseconds":repeated.elapsedMilliseconds,
                "preparationMilliseconds":repeated.preparationMilliseconds,"totalMilliseconds":repeated.totalMilliseconds,
                "usedCachedKeys":repeated.usedCachedKeys,"thermalStateBefore":repeated.thermalStateBefore,
                "thermalStateAfter":repeated.thermalStateAfter,"peakMemory":"not-measured"])
        }
        let repeats = XCTAttachment(data:try JSONSerialization.data(withJSONObject:repeatedMetrics,options:[.sortedKeys]),uniformTypeIdentifier:"public.json")
        repeats.name="native-proof-repeated-metrics.json";repeats.lifetime = .keepAlways
        add(repeats)
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
