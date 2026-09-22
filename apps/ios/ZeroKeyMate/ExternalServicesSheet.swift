import SwiftUI
import MateCore

struct ExternalServicesSheet: View {
    @ObservedObject var wallet: WalletService
    var requestedService: ConnectedPaymentService? = nil
    var onCompletion:(PaymentCompletion)->Void = {_ in}
    @StateObject private var checkout = ExternalCheckout()
    @ObservedObject private var store = ConnectedPaymentServices.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var adding = false
    @State private var email = ""
    @State private var sentTo: String?
    @State private var transaction = ""
    @FocusState private var hashFocused: Bool

    var body: some View {
        Form {
            if let error = checkout.error { Section { Text(error).foregroundStyle(.secondary) } }
            if checkout.busy { Section { ProgressView(L10n.text(checkout.phase)) } }
            if let result = checkout.completion {
                Section {
                    Label(L10n.text(result.receivedResult ? "Payment confirmed · Result received" : "Payment confirmed · Result unavailable"), systemImage: "checkmark.seal.fill")
                    Link("View transaction", destination: URL(string: "https://testnet.arcscan.app/tx/" + result.transaction)!)
                    if let body = result.response, result.receivedResult {
                        // Merchant output is displayed as plain text, never HTML,
                        // an instruction to the local model, or an executable URL.
                        Text(String(data: body, encoding: .utf8) ?? L10n.text("The service returned a binary result."))
                            .font(.body).textSelection(.enabled)
                    } else {
                        Text("The transfer is confirmed, but the service result was not received. A new purchase would be a separate payment.").font(.footnote)
                    }
                    Button("Back to services") { checkout.dismissQuote() }
                }
            } else if let pending = checkout.pending {
                Section("Previous payment") {
                    paymentDetails(pending.request)
                    Button("Check payment") { hashFocused = false; checkout.check(transaction: transaction.isEmpty ? nil : transaction) }
                        .disabled(checkout.busy)
                    if (UInt64(pending.authorization.validBefore) ?? 0) > UInt64(Date().timeIntervalSince1970) {
                        Button("Retry the same request") { checkout.retry() }.disabled(checkout.busy)
                    }
                    Button("Check expired authorization") { checkout.releaseExpired() }.disabled(checkout.busy)
                    DisclosureGroup("Transaction hash, if available") {
                        TextField("0x…", text: $transaction).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .focused($hashFocused).submitLabel(.done).onSubmit { hashFocused = false }
                    }
                }
            } else if let stalled = checkout.stalled {
                Section("Previous payment") {
                    paymentDetails(stalled.request)
                    if checkout.signingUncertain {
                        Text("Signing was interrupted. A signature may exist, so a new payment is blocked until its outcome is checked.")
                        Button("Check expired authorization") { checkout.releaseExpired() }.disabled(checkout.busy)
                    } else {
                        Text("Signing has not started. You can cancel this unfinished approval.")
                        Button("Cancel unfinished approval") { checkout.cancelUnsignedApproval() }.disabled(checkout.busy)
                    }
                }
            } else if let quote = checkout.quote {
                Section("Review this payment") {
                    paymentDetails(quote)
                    if wallet.ownerAddress == nil {
                        ShopWalletConnection(wallet: wallet, email: $email, sentTo: $sentTo)
                    } else {
                        Button("Approve exact payment") { checkout.approve(wallet: wallet) }
                            .disabled(checkout.busy).accessibilityIdentifier("external-approve")
                        if let payer = wallet.ownerAddress {
                            DisclosureGroup("Buyer wallet") {
                                ShareLink(item:payer) { Label(payer,systemImage:"square.and.arrow.up").font(.caption) }
                                Link("Get test USDC",destination:URL(string:"https://faucet.circle.com/")!)
                            }
                        }
                        Button("Cancel", role: .cancel) { checkout.dismissQuote() }.disabled(checkout.busy)
                    }
                }
            } else {
                Section {
                    if store.services.isEmpty { Text("Add an x402 service, then ask Mate to use it.").foregroundStyle(.secondary) }
                    ForEach(store.services) { service in
                        Button { checkout.prepare(service) } label: {
                            VStack(alignment: .leading) {
                                Text(service.name).font(.headline)
                                Text(service.payment.resource).font(.caption).foregroundStyle(.secondary)
                            }
                        }.disabled(checkout.busy)
                    }
                    .onDelete { indices in checkout.remove(indices.map { store.services[$0] }) }
                    Button("Add x402 service", systemImage: "plus") { adding = true }.disabled(checkout.busy)
                        .accessibilityIdentifier("external-add-service")
                }
                if !checkout.history.isEmpty {
                    Section("Recent payments") {
                        ForEach(checkout.history) { receipt in
                            Link(destination: URL(string: "https://testnet.arcscan.app/tx/" + receipt.transaction)!) {
                                VStack(alignment: .leading) {
                                    Text(receipt.request.service.resource).lineLimit(1)
                                    Text(Self.amount(receipt.authorization.value) + " test USDC").font(.caption)
                                }
                            }
                        }
                    }
                }
            }
            Section { Text("Arc Testnet · Test USDC only").font(.footnote).foregroundStyle(.secondary) }
        }
        .navigationTitle("Connected services").navigationBarTitleDisplayMode(.inline)
        .task {
            await checkout.restore(); try? await wallet.restore()
            if let requestedService, checkout.pending == nil, checkout.stalled == nil, checkout.quote == nil, checkout.completion == nil {
                checkout.prepare(requestedService)
            }
        }
        .sheet(isPresented: $adding) { NavigationStack { AddPaymentServiceSheet(checkout: checkout, store: store) } }
        .onDisappear { checkout.cancel() }
        .onChange(of:checkout.completion?.id) { _,id in
            if id != nil,let result=checkout.completion { onCompletion(result) }
        }
        // System owner authentication can temporarily make the scene inactive.
        // Only backgrounding abandons this approval; Face ID must be able to finish.
        .onChange(of: scenePhase) { _, value in if value == .background { checkout.cancel() } }
    }

    @ViewBuilder private func paymentDetails(_ request: PaymentRequest) -> some View {
        Text(Self.amount(request.accepted.amount) + " test USDC").font(.title2.bold())
        Text(request.service.resource).font(.callout).textSelection(.enabled)
        LabeledContent("Network", value: "Arc Testnet")
        VStack(alignment: .leading, spacing: 4) {
            Text("Recipient").font(.caption).foregroundStyle(.secondary)
            Text(request.service.recipient).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
        }
    }
    static func amount(_ value: String) -> String {
        guard let n = UInt64(value) else { return "—" }
        return String(format: "%.6f", Double(n) / 1_000_000)
    }
}

private struct AddPaymentServiceSheet: View {
    let checkout: ExternalCheckout
    @ObservedObject var store: ConnectedPaymentServices
    @Environment(\.dismiss) private var dismiss
    @State private var resource = ""
    @State private var name = ""
    @State private var ceiling = "0.10"
    @State private var quote: PaymentRequest?
    @State private var busy = false
    @State private var error: String?
    @State private var operation: Task<Void, Never>?
    @FocusState private var editing: Bool
    var body: some View {
        Form {
            if let quote {
                Section("Review service") {
                    Text(quote.service.resource).textSelection(.enabled)
                    TextField("Name used when speaking to Mate", text: $name).focused($editing)
                    LabeledContent("Maximum per purchase", value: ExternalServicesSheet.amount(String(quote.service.maximumAmount)) + " test USDC")
                    Text("Recipient").font(.caption)
                    Text(quote.service.recipient).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    Text("Adding a service does not authorize payments. Review each exact payment before signing.").font(.footnote)
                    Button("Add service") {
                        do { try store.add(name: name, quote: quote); dismiss() }
                        catch { self.error = L10n.text("The service could not be saved. Check its name and get a fresh quote.") }
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Change URL") { self.quote = nil }
                }
            } else {
                Section {
                    TextField("https://service.example/resource", text: $resource).keyboardType(.URL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().focused($editing)
                    TextField("Maximum test USDC", text: $ceiling).keyboardType(.decimalPad).focused($editing)
                    Button("Check service") {
                        editing = false; busy = true; error = nil
                        operation = Task {
                            defer { busy = false }
                            do {
                                guard let amount = Decimal(string: ceiling, locale: Locale(identifier: "en_US_POSIX")), amount > 0, amount <= Decimal(string: "0.50")! else {
                                    throw ExternalPaymentError.invalidService
                                }
                                let scaled = amount * 1_000_000
                                let units = NSDecimalNumber(decimal: scaled).uint64Value
                                guard Decimal(units) == scaled else { throw ExternalPaymentError.invalidService }
                                let discovered = try await checkout.discover(resource: resource.trimmingCharacters(in: .whitespacesAndNewlines), maximum: units)
                                try Task.checkCancellation()
                                quote = discovered
                                name = URL(string: discovered.service.resource)?.host ?? ""
                            } catch { self.error = L10n.text("This endpoint did not offer a supported Arc Testnet USDC payment within your limit.") }
                        }
                    }.disabled(busy || resource.isEmpty)
                    if busy { ProgressView() }
                }
            }
            if let error { Text(error).foregroundStyle(.secondary) }
        }.navigationTitle("Add x402 service")
        .onDisappear { operation?.cancel() }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { editing = false } }
        }
    }
}
