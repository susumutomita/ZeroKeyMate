import Foundation
import SwiftUI
import MateCore

@MainActor
final class ProofInspectionModel: ObservableObject {
    @Published var budget = "5"
    @Published var amount = "3"
    @Published var spent = "0"
    @Published var allowsSummary = true
    @Published private(set) var busy = false
    @Published private(set) var result: VerifiedLocalProof?
    @Published private(set) var tamperingRejected = false
    @Published private(set) var error: String?
    func clear() { result = nil; tamperingRejected = false; error = nil }
    func run() async {
        guard !busy else { return }
        busy = true; clear(); defer { busy = false }
        do {
            let policy = try PrivatePolicy(budget: TokenAmount(decimal: budget).units,
                services: allowsSummary ? 3 : 1, salt: LocalSecrets.random32())
            let spentValue: UInt64
            if ["0", "0.0", "0.00", "0.000", "0.0000", "0.00000", "0.000000"].contains(spent) {
                spentValue = 0
            } else { spentValue = try TokenAmount(decimal: spent).units }
            // These locally generated identifiers are NOT presented as registered accounts.
            // This screen performs no network requests or financial operations.
            let action = MandateAction(mandateId: CanonicalBytes.hexString(try LocalSecrets.random32()),
                recipient: "0x" + String(repeating: "11", count: 20),
                amount: try TokenAmount(decimal: amount).units, service: .summary,
                nonce: CanonicalBytes.hexString(try LocalSecrets.random32()),
                expiresAt: UInt64(Date().timeIntervalSince1970) + 3600,
                requestHash: LocalSecrets.hash(Data("Local inspection, not a payment.".utf8)), spentBefore: spentValue)
            let proof = try await ProofService.shared.prove(policy: policy, action: action,
                chainID: 11_155_111, vault: "0x" + String(repeating: "22", count: 20))
            guard try await ProofService.shared.rejectsTampering(proof: proof.bytes) else { throw ProductError.invalidResponse }
            result = proof; tamperingRejected = true
        } catch { self.error = error.localizedDescription }
    }
}
struct ProofInspectionView: View {
    @StateObject private var model = ProofInspectionModel()
    var body: some View {
        Form {
            Section {
                Text("秘密のまま、\n確かめる。").font(.largeTitle.weight(.regular)).tracking(-0.8).padding(.vertical, 12)
                Text("この端末で実際に生成・検証します。結果・処理時間・証明サイズは実測値です。")
                    .font(.subheadline).foregroundStyle(.secondary)
                Label("外部送信・署名・支払いなし", systemImage: "iphone").font(.footnote)
            }
            Section("端末内に残る条件") {
                amountField("利用上限", value: $model.budget)
                Toggle("要約を許可", isOn: $model.allowsSummary)
            }
            Section("検証対象") {
                amountField("利用済み", value: $model.spent)
                amountField("今回の金額", value: $model.amount)
                LabeledContent("サービス", value: "要約")
                Text("検証専用の識別子を使います。オンチェーンの取引としては記録しません。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Button { Task { await model.run() } } label: {
                    HStack {
                        Spacer()
                        if model.busy { ProgressView().tint(Finish.paper) }
                        Text(model.busy ? "端末内で検証中" : "証明を生成して検証").font(.body.weight(.semibold))
                        Spacer()
                    }.frame(minHeight: 52).foregroundStyle(Finish.paper)
                        .background(Finish.ink, in: RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(.plain).accessibilityIdentifier("inspect-proof")
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            if let proof = model.result {
                Section("検証結果") {
                    Label("証明は有効です", systemImage: "checkmark.shield").accessibilityIdentifier("inspection-valid")
                    LabeledContent("生成・検証時間", value: "\(proof.elapsedMilliseconds) ms")
                    LabeledContent("証明サイズ", value: "\(proof.bytes.count.formatted()) bytes")
                    if model.tamperingRejected { Label("改変した証明を拒否", systemImage: "shield.lefthalf.filled") }
                }
                hashSection("条件のコミットメント", value: proof.policyHash)
                hashSection("実行内容のハッシュ", value: proof.actionHash)
                hashSection("証明のハッシュ", value: proof.proofHash)
            }
            if let error = model.error {
                Section("検証を完了できませんでした") {
                    Text(error).accessibilityIdentifier("inspection-error")
                    Text("条件不適合はローカルチェックで止めます。環境エラーも成功した証明として扱いません。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }.disabled(model.busy).scrollContentBackground(.hidden).background(Finish.paper)
            .navigationTitle("証明を確かめる").navigationBarTitleDisplayMode(.inline)
            .onChange(of: model.budget) { _, _ in model.clear() }
            .onChange(of: model.amount) { _, _ in model.clear() }
            .onChange(of: model.spent) { _, _ in model.clear() }
            .onChange(of: model.allowsSummary) { _, _ in model.clear() }
    }
    private func amountField(_ name: String, value: Binding<String>) -> some View {
        HStack {
            Text(name); Spacer()
            TextField(name, text: value).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 110)
            Text("USDC").foregroundStyle(.secondary)
        }
    }
    private func hashSection(_ title: String, value: String) -> some View {
        Section(title) { Text(value).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
    }
}
