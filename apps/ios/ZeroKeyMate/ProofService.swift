import CryptoKit
import Foundation
import MateCore
import Verity

struct VerifiedLocalProof: Sendable {
    let bytes: Data
    let policyHash: String
    let actionHash: String
    let elapsedMilliseconds: Int
    var proofHash: String { LocalSecrets.hash(bytes) }
}

/// Native proving is isolated from the UI and networking. Witnesses never leave this actor.
actor ProofService {
    struct Manifest: Decodable {
        let system: String
        let version: String
        let circuit: String
        let hash: String
        let files: [String:String]
    }
    private var keyData: (Data,Data)?
    func prepare() throws {
        guard Verity.runtimeMode == .native else {
            throw ProductError.unavailable("端末内の証明ランタイムは未導入です。make native-runtime と make proofs を実行して再ビルドしてください。")
        }
        guard keyData == nil else { return }
        guard let manifestURL = Bundle.main.url(forResource: "manifest", withExtension: "json"),
              let proverURL = Bundle.main.url(forResource: "mate_policy", withExtension: "pkp"),
              let verifierURL = Bundle.main.url(forResource: "mate_policy", withExtension: "pkv") else {
            throw ProductError.unavailable("証明用ファイルがありません。make proofs を実行して再ビルドしてください。")
        }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.system == "ProveKit", manifest.version == "1.0.1",
              manifest.circuit == "mate_policy", manifest.hash == "skyscraper" else { throw ProductError.invalidResponse }
        let prover = try Data(contentsOf: proverURL, options: .mappedIfSafe)
        let verifier = try Data(contentsOf: verifierURL, options: .mappedIfSafe)
        for (name,data) in [("mate_policy.pkp",prover),("mate_policy.pkv",verifier)] {
            guard let expected = manifest.files[name], expected.count == 64,
                  String(LocalSecrets.hash(data).dropFirst(2)) == expected else { throw ProductError.invalidResponse }
        }
        let runtime=try Verity(backend:.provekit)
        let loadedProver=try runtime.loadProver(data:prover)
        defer{loadedProver.close()}
        let loadedVerifier=try runtime.loadVerifier(data:verifier)
        loadedVerifier.close()
        keyData = (prover,verifier)
    }
    func prove(policy: PrivatePolicy, action: MandateAction, chainID: UInt64, vault: String) throws -> VerifiedLocalProof {
        try Task.checkCancellation()
        try prepare()
        guard let keys = keyData, let amount = UInt64(action.amount), let spent = UInt64(action.spentBefore),
              let service = MateService(rawValue: action.service) else { throw ProductError.invalidResponse }
        try policy.check(spent: spent, amount: amount, service: service)
        let policyHash = LocalSecrets.hash(try policy.material())
        let actionHash = LocalSecrets.hash(try action.material(chainID: chainID, vault: vault))
        let values: [String:Any] = [
            "policy_hash": Array(try CanonicalBytes.hex(policyHash,count:32)),
            "action_hash": Array(try CanonicalBytes.hex(actionHash,count:32)),
            "spent": String(spent), "amount": String(amount), "service": String(action.service),
            "budget": String(policy.budget), "services": String(policy.services), "salt": Array(policy.salt),
            "context": Array(try action.context(chainID: chainID,vault: vault))
        ]
        let witness = try Witness(json: String(decoding: JSONSerialization.data(withJSONObject: values), as: UTF8.self))
        let runtime = try Verity(backend: .provekit)
        let prover = try runtime.loadProver(data: keys.0)
        defer { prover.close() }
        let verifier = try runtime.loadVerifier(data: keys.1)
        defer { verifier.close() }
        let start = Date()
        let proof = try prover.prove(witness: witness)
        guard try verifier.verify(proof: proof) else { throw ProductError.invalidResponse }
        try Task.checkCancellation()
        return VerifiedLocalProof(bytes: proof.data, policyHash: policyHash, actionHash: actionHash,
            elapsedMilliseconds: Int(Date().timeIntervalSince(start) * 1000))
    }
}
