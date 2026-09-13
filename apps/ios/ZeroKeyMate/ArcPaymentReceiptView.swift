import SwiftUI
import UIKit

/// A public transaction reference, shared by checkout and purchase history.
struct ArcPaymentReceiptView: View {
    let transaction: String
    @State private var copied = false

    private var explorerURL: URL? {
        guard transaction.range(of: #"^0x[0-9a-fA-F]{64}$"#, options: .regularExpression) != nil else { return nil }
        return URL(string: "https://testnet.arcscan.app/tx/" + transaction)
    }

    var body: some View {
        if let explorerURL {
            VStack(alignment: .leading, spacing: 12) {
                Link(destination: explorerURL) {
                    Label("View transaction on Arc Explorer", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.bordered).tint(.blue)
                .accessibilityIdentifier("shop-transaction-link")
                Text("Transaction hash").font(.caption).foregroundStyle(.secondary)
                Text(transaction).font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("shop-transaction-hash")
                Button {
                    UIPasteboard.general.string = transaction
                    copied = true
                } label: {
                    Label(copied ? LocalizedStringKey("Copied") : LocalizedStringKey("Copy transaction hash"), systemImage: copied ? "checkmark" : "doc.on.doc")
                        .frame(minHeight: 32)
                }
                .buttonStyle(.borderless).tint(.blue)
                .accessibilityIdentifier("shop-copy-transaction")
            }
            .onChange(of: transaction) { _, _ in copied = false }
        }
    }
}
