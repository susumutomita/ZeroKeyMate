import Combine
import Foundation
import MateCore

/// An offline exercise of the production circuit. No wallet, RPC or HTTP dependency.
@MainActor
final class LocalProofModel: ObservableObject {
    struct Evidence {
        let proof: VerifiedLocalProof
        let tamperedProofRejected: Bool
    }
    @Published private(set) var running = false
    @Published private(set) var evidence: Evidence?
    @Published private(set) var message: String?
    private let proofs = ProofService()
    private var task: Task<Void, Never>?
    private var generation = UUID()

    func invalidate() {
        generation = UUID()
        task?.cancel()
        evidence = nil
        message = running ? "Result discarded. Native computation may still be finishing." : nil
    }

    func prove(budget: String, amount: String, allowsTranslation: Bool) {
        guard !running else { return }
        evidence = nil
        message = nil
        do {
            let policy = try PrivatePolicy(budget: TokenAmount(decimal: budget).units,
                services: allowsTranslation ? 3 : MateService.summary.bit, salt: LocalSecrets.random32())
            let price = try TokenAmount(decimal: amount).units
            // Preflight rejection is explicitly distinguished from verifier rejection in the UI.
            try policy.check(spent: 0, amount: price, service: .translation)
            let action = MandateAction(mandateId: LocalSecrets.hash(try LocalSecrets.random32()),
                recipient: "0x0000000000000000000000000000000000000001", amount: price,
                service: .translation, nonce: CanonicalBytes.hexString(try LocalSecrets.random32()),
                expiresAt: UInt64(Date().timeIntervalSince1970) + 300,
                requestHash: LocalSecrets.hash(Data("Offline translation challenge".utf8)), spentBefore: 0)
            let ticket = UUID()
            generation = ticket
            running = true
            task = Task {
                defer { running = false; task = nil }
                do {
                    let proof = try await proofs.prove(policy: policy, action: action, chainID: 11_155_111,
                        vault: "0x0000000000000000000000000000000000000002")
                    try Task.checkCancellation()
                    let rejected = try await proofs.rejectsTamperedCopy(of: proof)
                    guard generation == ticket, !Task.isCancelled else { return }
                    guard rejected else { throw ProductError.invalidResponse }
                    evidence = Evidence(proof: proof, tamperedProofRejected: rejected)
                } catch {
                    guard generation == ticket, !Task.isCancelled else { return }
                    message = error.localizedDescription
                }
            }
        } catch {
            message = "No proof generated. " + error.localizedDescription
        }
    }
}
