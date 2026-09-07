import SwiftUI

struct LocalProofSheet: View {
    @StateObject private var model = LocalProofModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var budget = "5"
    @State private var amount = "0.01"
    @State private var allowsTranslation = true

    var body: some View {
        Form {
            Section {
                Text("Prove permission.\nKeep your rules private.").font(.title2)
                Text("Create and verify a real ProveKit proof on this device. After installation, this exercise also works in airplane mode.")
                Text("Offline proof exercise · No payment or signature").font(.caption).foregroundStyle(.secondary)
            }
            Section("1. Private inputs — stay on this device") {
                TextField("Private spending limit (USDC)", text: $budget)
                    .keyboardType(.decimalPad).accessibilityIdentifier("proof-budget")
                Toggle("Allow translation", isOn: $allowsTranslation)
                Text("Your limit, full permission set and random secret salt are private circuit inputs. A fresh salt prevents guessing a small budget from its commitment.").font(.footnote)
            }.disabled(model.running)
            Section("2. Public request") {
                TextField("Translation price (USDC)", text: $amount)
                    .keyboardType(.decimalPad).accessibilityIdentifier("proof-amount")
                Text("Translation · Previously spent: 0 USDC")
                Text("This exercise generates a fresh request ID and uses example Sepolia addresses. It cannot authorize a payment. In the payment flow, the proof binds the actual network, vault, recipient, price, text hash, expiry and replay ID.").font(.footnote)
            }.disabled(model.running)
            Section("3. Prove locally") {
                Button("Generate and verify proof") {
                    model.prove(budget: budget, amount: amount, allowsTranslation: allowsTranslation)
                }.disabled(model.running).accessibilityIdentifier("generate-local-proof")
                if model.running {
                    ProgressView("Computing on this device…")
                    Button("Discard this run", role: .cancel) { model.invalidate() }
                    Text("Native proving may take time. Discarding hides its result; it cannot interrupt a native call already in progress.").font(.footnote)
                }
                if let message = model.message { Text(message).accessibilityIdentifier("local-proof-message") }
            }
            if let evidence = model.evidence {
                Section("Verified on this device") {
                    Label("Original proof accepted", systemImage: "checkmark.shield")
                    Label("Modified proof rejected", systemImage: "xmark.shield")
                    LabeledContent("Prove + verify", value: "\(evidence.proof.elapsedMilliseconds) ms")
                    LabeledContent("Proof size", value: "\(evidence.proof.bytes.count) bytes")
                    Text("Measured on this device for this run. Modified-proof checking is excluded from the time above.").font(.footnote)
                }.accessibilityIdentifier("local-proof-evidence")
                Section("What a verifier sees") {
                    Text("Policy commitment").font(.caption)
                    Text(evidence.proof.policyHash).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    Text("Request commitment").font(.caption)
                    Text(evidence.proof.actionHash).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    Text("Proof SHA-256").font(.caption)
                    Text(evidence.proof.proofHash).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    Text("A payment verifier also receives the public request, price and prior spending. Successful requests can reveal a lower bound on your budget. ZK does not hide public payments or encrypt the text sent to a provider.").font(.footnote)
                }
            }
            Section("Try the boundary") {
                Text("Set the price above your limit, or turn off translation. Mate refuses to generate a proof at preflight. That local refusal is separate from the cryptographic modified-proof check above.")
                Text("Settlement currently relies on the server verifier's signed attestation; the vault does not verify ProveKit proofs directly. This exercise demonstrates the native circuit, not server or blockchain enforcement.").font(.footnote)
            }
        }
        .navigationTitle("Local ZK").navigationBarTitleDisplayMode(.inline)
        .onChange(of: budget) { _, _ in model.invalidate() }
        .onChange(of: amount) { _, _ in model.invalidate() }
        .onChange(of: allowsTranslation) { _, _ in model.invalidate() }
        .onChange(of: scenePhase) { _, phase in if phase == .background { model.invalidate() } }
        .onDisappear { model.invalidate() }
    }
}
