import SwiftUI

struct LocalProofSheet: View {
    let requestTranslation: () -> Void
    @StateObject private var model: LocalProofModel

    init(proofs: ProofService, requestTranslation: @escaping () -> Void) {
        _model = StateObject(wrappedValue: LocalProofModel(proofs: proofs))
        self.requestTranslation = requestTranslation
    }
    @Environment(\.scenePhase) private var scenePhase
    @State private var budget = "5"
    @State private var amount = "0.01"
    @State private var allowsTranslation = true

    var body: some View {
        VStack(spacing:0) {
        Form {
            Section {
                Text("Prove permission.\nKeep your rules private.").font(.title2)
                Text("Create and verify a real ProveKit proof on this device. After installation, this exercise also works in airplane mode.")
                Text("Offline proof exercise · No payment or signature").font(.caption).foregroundStyle(.secondary)
            }
            Section("1. Private inputs — stay on this device") {
                HStack {
                    Text("Spending limit")
                    TextField("USDC", text: $budget).multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad).accessibilityIdentifier("proof-budget")
                    Text("USDC")
                }
                Toggle("Allow translation", isOn: $allowsTranslation)
                Text("Your limit, full permission set and random secret salt are private circuit inputs. A fresh salt prevents guessing a small budget from its commitment.").font(.footnote)
            }.disabled(model.running)
            Section("2. Public request") {
                HStack {
                    Text("Translation price")
                    TextField("USDC", text: $amount).multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad).accessibilityIdentifier("proof-amount")
                    Text("USDC")
                }
                Text("Translation · Previously spent: 0 USDC")
                Text("This exercise generates a fresh request ID and uses example Sepolia addresses. It cannot authorize a payment. In the payment flow, the proof binds the actual network, vault, recipient, price, text hash, expiry and replay ID.").font(.footnote)
            }.disabled(model.running)
            if let evidence = model.evidence {
                Section("Verified on this device") {
                    Label("Original proof accepted", systemImage: "checkmark.shield")
                    Label("Modified proof rejected", systemImage: "xmark.shield")
                    LabeledContent("Prove + verify", value: L10n.format("%lld ms",evidence.proof.elapsedMilliseconds))
                    LabeledContent("Proof size", value: L10n.format("%lld bytes",evidence.proof.bytes.count))
                    Text("Measured on this device for this run. Modified-proof checking is excluded from the time above.").font(.footnote)
                }.accessibilityIdentifier("local-proof-evidence")
                Section("Verify independently") {
                    Text("Export only the proof and its embedded public inputs. Your private rule values and salt are not included. Anyone with this circuit's matching verifier key can verify the file.").font(.footnote)
                    if let url = model.exportURL {
                        ShareLink("Share proof file", item: url)
                    } else {
                        Button("Prepare proof file for sharing") { model.prepareExport() }
                    }
                }
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
            Section("Use private rules for a real request") {
                Button("Review a translation request", action: requestTranslation)
                    .accessibilityIdentifier("proof-to-translation").disabled(model.running)
                Text("The paid flow requires a configured execution service, wallet funds and a separately approved mandate. This offline exercise does not create that approval.").font(.footnote)
            }
            Section("Try the boundary") {
                Text("Set the price above your limit, or turn off translation. Mate refuses to generate a proof at preflight. That local refusal is separate from the cryptographic modified-proof check above.")
                Text("Settlement currently relies on the server verifier's signed attestation; the vault does not verify ProveKit proofs directly. This exercise demonstrates the native circuit, not server or blockchain enforcement.").font(.footnote)
            }
        }
            VStack(spacing: 8) {
                Button("Generate and verify proof") {
                    model.prove(budget: budget, amount: amount, allowsTranslation: allowsTranslation)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(model.running).accessibilityIdentifier("generate-local-proof")
                if model.running {
                    ProgressView("Computing on this device…")
                    Button("Discard this run", role: .cancel) { model.invalidate() }
                    Text("Discarding hides the result. A native call already in progress must finish.").font(.caption)
                }
                if model.evidence != nil {
                    Label("Proof verified. Scroll to inspect and share.",systemImage:"checkmark.shield")
                        .font(.footnote).accessibilityIdentifier("local-proof-ready")
                }
                if let message = model.message {
                    Text(L10n.text(message)).font(.footnote).accessibilityIdentifier("local-proof-message")
                }
            }
            .frame(maxWidth: .infinity).padding().background(.regularMaterial)
        }
        .navigationTitle("Local ZK").navigationBarTitleDisplayMode(.inline)
        .onChange(of: budget) { _, _ in model.invalidate() }
        .onChange(of: amount) { _, _ in model.invalidate() }
        .onChange(of: allowsTranslation) { _, _ in model.invalidate() }
        .onChange(of: scenePhase) { _, phase in if phase == .background { model.invalidate() } }
        .onDisappear { model.invalidate() }
    }
}
