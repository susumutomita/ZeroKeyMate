import SwiftUI
import MateCore

struct ShopPurchaseSheet: View {
    @ObservedObject var model: CompanionModel
    @ObservedObject var wallet: WalletService
    @StateObject private var checkout = ShopCheckout()
    @StateObject private var pinEntry = SignaturePINEntry()
    @State private var automaticOrderStarted = false
    // Keep the destination across the temporary checking phase when the user
    // returns from Mail. The one-use code remains local to the child view.
    @State private var buyerEmail = ""
    @State private var buyerCodeSentTo: String?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale

    private var heading: String {
        switch checkout.phase {
        case .initial,.checking: return "Opening the store"
        case .review: return "Let Mate get your order"
        case .funding: return "Add free test USDC"
        case .card: return "Confirm you're 20 or older"
        case .preparingCard: return "Preparing the card scanner"
        case .readingCard: return "Hold your card to the phone"
        case .proving: return "Your phone is making the proof"
        case .proofFailed: return "Age proof could not be completed"
        case .verifying: return "The store is checking your proof"
        case .verificationFailed: return "Waiting for age verification"
        case .paymentApproval: return "Approve the exact payment"
        case .paying: return "Mate is paying the store"
        case .pending: return "Checking your payment"
        case .complete: return "Your test purchase is complete"
        case .expired: return "The payment window closed"
        case .unavailable: return "The store is not ready yet"
        }
    }
    var body: some View {
        // Dynamic phase/error strings use L10n; observe the locale so they
        // refresh alongside SwiftUI's static text in the existing checkout.
        let _ = locale.identifier
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 20) {
                    Image(systemName: checkout.phase == .complete ? "checkmark.seal.fill" : (checkout.selection.requiresAgeProof ? "mug.fill" : "drop.fill"))
                        .font(.system(size: 48)).foregroundStyle(checkout.phase == .complete ? Color.green : Color.orange)
                        .frame(width: 88, height: 100).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(checkout.selection.product.name).font(.title2.bold())
                        Text(checkout.selection.quantity == 1
                             ? L10n.format("One bottle · %@", checkout.selection.product.size)
                             : L10n.format("%lld bottles · %@ each", Int64(checkout.selection.quantity), checkout.selection.product.size))
                            .foregroundStyle(.secondary).accessibilityIdentifier("shop-product-size")
                        Text("\(checkout.selection.displayAmount) test USDC").font(.headline)
                    }
                }
                Text(L10n.text(heading)).font(.title2.bold()).accessibilityIdentifier("shop-phase")
                if let message = checkout.message {
                    Text(L10n.text(message)).foregroundStyle(.secondary).accessibilityIdentifier("shop-message")
                }
                switch checkout.phase {
                case .review:
                    Picker("Product", selection: Binding(get: { checkout.selection.product }, set: { product in
                        if let selection = try? ShopSelection(product: product, quantity: checkout.selection.quantity) { checkout.select(selection) }
                    })) {
                        ForEach(ShopProduct.allCases, id: \.self) { product in Text(product.name).tag(product) }
                    }.disabled(checkout.busy).accessibilityIdentifier("shop-product")
                    Stepper(L10n.format("Quantity: %lld", Int64(checkout.selection.quantity)), value: Binding(get: { checkout.selection.quantity }, set: { quantity in
                        if let selection = try? ShopSelection(product: checkout.selection.product, quantity: quantity) { checkout.select(selection) }
                    }), in: 1...ShopSelection.maximumQuantity).disabled(checkout.busy).accessibilityIdentifier("shop-quantity")
                    Text(L10n.text(checkout.selection.requiresAgeProof ? "This product requires proof that you are 20 or older." : "No age verification or card scan needed."))
                    if wallet.ownerAddress == nil {
                        ShopWalletConnection(wallet: wallet, email: $buyerEmail, sentTo: $buyerCodeSentTo)
                    } else {
                        Button(L10n.format("Start this order · %@ test USDC", checkout.selection.displayAmount)) { checkout.startOrder(wallet: wallet) }
                            .buttonStyle(.borderedProminent).accessibilityIdentifier("shop-start-order")
                    }
                case .funding:
                    Text(L10n.format("Your buyer wallet needs %@ test USDC on Arc Testnet. The store pays the network fee. No order has been created yet.", checkout.selection.displayAmount))
                    if let address = checkout.fundingAddress {
                        Text(address).font(.footnote.monospaced()).textSelection(.enabled)
                        ShareLink(item: address) { Label("Share buyer address", systemImage: "square.and.arrow.up") }
                    }
                    Link("Get free test USDC from Circle", destination: URL(string: "https://faucet.circle.com/")!)
                    Text("Choose Arc Testnet and paste this buyer address. Return here after the faucet transfer.").foregroundStyle(.secondary)
                    Button("Check funds and start this order") { checkout.startOrder(wallet: wallet) }
                        .buttonStyle(.borderedProminent).disabled(checkout.busy)
                case .card:
                    SignaturePINField(entry: pinEntry, submit: startCardRead)
                case .proofFailed:
                    if checkout.canRetryAgeProof {
                        Button("Retry proof without scanning") { checkout.retryAgeProof() }
                            .buttonStyle(.borderedProminent).disabled(checkout.busy)
                    } else {
                        Button("Read the card again") { checkout.restartCardRead() }.disabled(checkout.busy)
                    }
                    Button("Back to Mate") { model.sheet = nil }
                case .verificationFailed:
                    if checkout.canRetryAgeSubmission {
                        Button("Send the same proof again") { checkout.retryAgeSubmission() }
                            .buttonStyle(.borderedProminent).disabled(checkout.busy)
                    }
                    Button("Check the same order") { checkout.checkOrder() }.disabled(checkout.busy)
                    Button("Back to Mate") { model.sheet = nil }
                case .preparingCard,.readingCard,.proving,.verifying,.paying,.checking,.initial:
                    ProgressView().controlSize(.large)
                    Text(L10n.text(progressDetail)).foregroundStyle(.secondary)
                    if checkout.phase == .proving, let start = checkout.proofStartedAt {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            let seconds = Double(AgeProofTiming.milliseconds(start.duration(to: .now))) / 1_000
                            Text(L10n.format("Working locally · %.0f s", seconds))
                                .monospacedDigit().foregroundStyle(.secondary)
                                .accessibilityIdentifier("shop-proof-elapsed")
                        }
                    }
                case .paymentApproval:
                    Text(L10n.text(checkout.selection.requiresAgeProof ? "Age verified. Approve this one purchase." : "No age verification needed. Approve this one purchase."))
                    Button(L10n.format("Approve %@ test USDC", checkout.selection.displayAmount)) { checkout.continuePayment(wallet: wallet) }
                        .buttonStyle(.borderedProminent).disabled(checkout.busy)
                case .pending:
                    if checkout.busy { ProgressView() }
                    Text("Keep this order. Closing this screen does not undo a payment already sent.").foregroundStyle(.secondary)
                    Button("Check the same order") { checkout.checkOrder() }.buttonStyle(.borderedProminent).disabled(checkout.busy)
                    if checkout.canRetryOriginal {
                        Button("Retry the original payment") { checkout.retryOriginalPayment() }.disabled(checkout.busy)
                    }
                case .complete:
                    Text(L10n.text(checkout.selection.requiresAgeProof ? "Paid. Your birth date stayed on your iPhone." : "Paid. No identity document was needed."))
                    if let hash = checkout.order?.paymentTransaction {
                        ArcPaymentReceiptView(transaction: hash)
                    }
                    Button("Back to Mate") { model.sheet = nil }.buttonStyle(.borderedProminent)
                case .unavailable:
                    Text("You can close this screen. Mate hasn't completed a purchase.").foregroundStyle(.secondary)
                    Button("Check again") { checkout.retryAvailability() }.buttonStyle(.borderedProminent).disabled(checkout.busy)
                case .expired:
                    Text("The original authorization expired without being used. Mate checked the finalized network record; this order was not paid.")
                }
                if let timing = checkout.proofTiming {
                    Label(L10n.format("Age proof made on this phone · %.1f s", Double(timing.totalMilliseconds) / 1_000),
                          systemImage: "checkmark.shield")
                        .font(.subheadline).accessibilityIdentifier("shop-proof-duration")
                }
                if checkout.canStartNew {
                    Button("Start a new order") { pinEntry.clear(); checkout.startNew() }.disabled(checkout.busy)
                }
                DisclosureGroup("Purchase details") {
                    VStack(alignment: .leading, spacing: 12) {
                        if let code = checkout.proofFailureCode {
                            Text(code).font(.footnote.monospaced()).textSelection(.enabled)
                                .accessibilityIdentifier("shop-proof-failure-code")
                        }
                        if let timing = checkout.proofTiming, let phases = timing.nativePhases {
                            DisclosureGroup("Proof timing") {
                                VStack(alignment: .leading, spacing: 8) {
                                    LabeledContent("Total on this phone", value: L10n.format("%lld ms", timing.totalMilliseconds))
                                    LabeledContent("Prover setup", value: proofDuration(phases.proverLoadMicroseconds))
                                    LabeledContent("Input preparation", value: proofDuration(phases.inputParseMicroseconds))
                                    LabeledContent("Witness and proof", value: proofDuration(phases.witnessAndProofMicroseconds))
                                    LabeledContent("Verifier key loading", value: proofDuration(phases.verifierLoadMicroseconds))
                                    LabeledContent("Local verification", value: proofDuration(phases.verificationMicroseconds))
                                    LabeledContent("Proof encoding", value: proofDuration(phases.encodingMicroseconds))
                                    Text("Groth16 · 2 threads. Witness/proof time includes key pages loaded on demand.")
                                        .font(.caption)
                                }.padding(.top, 8)
                            }.accessibilityIdentifier("shop-proof-timing")
                        }
                        if let url = checkout.storeURL {
                            Link(destination: url) { Label(url.host ?? "Store", systemImage: "arrow.up.right") }
                        }
                        if checkout.selection.requiresAgeProof {
                            privacy
                            Text("Use the signature password: 6–16 uppercase letters and numbers. This is different from the four-digit card PIN.")
                        } else {
                            Text("This order does not request your card or personal details.")
                        }
                        Text("Only this order is authorized. The store pays the network fee.")
                    }.font(.subheadline).padding(.top, 8)
                }.font(.subheadline).foregroundStyle(.secondary)
                Text("Arc Testnet · No real money · No physical delivery")
                    .font(.footnote).foregroundStyle(.secondary)
            }.frame(maxWidth: 520, alignment: .leading).padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            if checkout.phase == .card {
                SignaturePINScanButton(busy: checkout.busy, submit: startCardRead)
            }
        }
        .navigationTitle(L10n.text("Mate's order")).navigationBarTitleDisplayMode(.inline)
        .controlSize(.large)
        .task { checkout.select(model.shopSelection); checkout.load() }
        .onChange(of: checkout.phase) { _, phase in
            // A fresh voice request may first recover a completed/expired old
            // order. Its terminal phase is not the result of the new request.
            let replacingOldOrder = model.shopStartsFromVoice && !automaticOrderStarted && checkout.canStartNew
            advanceVoiceOrder()
            if !replacingOldOrder && checkout.phase == phase { model.guideShop(phase) }
        }
        .onChange(of: checkout.busy) { _, _ in advanceVoiceOrder() }
        .onChange(of: wallet.ownerAddress) { _, _ in advanceVoiceOrder() }
        .onDisappear {
            let completed = checkout.phase == .complete
            pinEntry.clear(); buyerEmail = ""; buyerCodeSentTo = nil; checkout.cancel()
            if !completed { model.voice.stop() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { pinEntry.clear(); checkout.cancel() }
            else if phase == .active { checkout.load() }
        }
    }
    private func advanceVoiceOrder() {
        // A current, explicit catalogue request may create its order after
        // readiness/funds checks. It does not authorize a payment signature.
        guard model.shopStartsFromVoice, !automaticOrderStarted,
              !checkout.busy,
              wallet.ownerAddress != nil else { return }
        // A fresh, explicit voice order may replace a safely terminal order.
        // An uncertain payment never satisfies canStartNew and remains intact.
        if checkout.canStartNew { pinEntry.clear(); checkout.startNew(); return }
        guard checkout.phase == .review, checkout.canStart else { return }
        automaticOrderStarted = true
        checkout.startOrder(wallet: wallet)
    }
    private func proofDuration(_ microseconds: UInt64) -> String {
        L10n.format("%.1f ms", Double(microseconds) / 1_000)
    }
    private func startCardRead() {
        guard checkout.phase == .card else { return }
        pinEntry.submit(busy: checkout.busy) { oneUse in
            checkout.readCard(pin: oneUse, sensors: model.sensors)
        }
    }
    private var privacy: some View {
        Label("Your name, address and birth date stay on this phone. The store receives the age proof, not your card.", systemImage: "lock.shield")
            .font(.subheadline).foregroundStyle(.secondary)
    }
    private var progressDetail: String {
        switch checkout.phase {
        case .preparingCard: return "Keep Mate open. The scanner will appear shortly."
        case .readingCard: return "Hold the card against the top of your iPhone."
        case .proving: return "Keep Mate open. Your birth date stays here."
        case .verifying: return "Only the public proof is sent to the store."
        case .paying: return "Waiting for the payment receipt."
        default: return "One moment."
        }
    }
}

/// Purchase-specific onboarding keeps the user in the order and does not
/// require a specialist API, policy vault, deposit approval or execution key.
struct ShopWalletConnection: View {
    @ObservedObject var wallet: WalletService
    @Binding var email: String
    @State private var code = ""
    @Binding var sentTo: String?
    @State private var message: String?
    @State private var operation: Task<Void, Never>?
    private enum Field { case email, code }
    @FocusState private var focusedField: Field?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect with Privy").font(.headline)
            Text("First time only: sign in with your email.")
                .font(.subheadline).foregroundStyle(.secondary)
            if wallet.isAuthenticated {
                Button("Prepare buyer wallet") { run { try await wallet.prepareShopWallet() } }
                    .buttonStyle(.borderedProminent)
            } else if let sentTo {
                TextField("Verification code", text: $code)
                    .keyboardType(.asciiCapableNumberPad).textContentType(.oneTimeCode)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .privacySensitive().focused($focusedField, equals: .code)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("shop-login-code")
                    .onChange(of: code) { _, value in
                        let digits = String(value.filter { $0.isASCII && $0.isNumber }.prefix(6))
                        if code != digits { code = digits }
                        if digits.count == 6 { focusedField = nil }
                    }
                Button("Sign in and prepare buyer wallet") {
                    focusedField = nil
                    let oneUse = code; code = ""
                    run {
                        try await wallet.login(email: sentTo, code: oneUse)
                        try Task.checkCancellation()
                        try await wallet.prepareShopWallet()
                    }
                }.buttonStyle(.borderedProminent).disabled(code.count != 6)
                Button("Use a different email") { self.sentTo = nil; code = ""; message = nil }
            } else {
                TextField("Email address", text: $email).keyboardType(.emailAddress)
                    .focused($focusedField, equals: .email)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                Button("Send verification code") {
                    focusedField = nil
                    let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
                    run { try await wallet.sendCode(email: address); try Task.checkCancellation(); sentTo = address }
                }.buttonStyle(.borderedProminent).disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if operation != nil || wallet.busy { ProgressView() }
            if let message { Text(L10n.text(message)).foregroundStyle(.secondary) }
        }
        .disabled(operation != nil || wallet.busy)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if focusedField != nil {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
        }
        .onDisappear { operation?.cancel(); code = "" }
    }
    private func run(_ body: @escaping @MainActor () async throws -> Void) {
        guard operation == nil else { return }
        message = nil
        operation = Task { @MainActor in
            defer { operation = nil }
            do { try await body() }
            catch is CancellationError { }
            catch { message = "Wallet connection did not finish. Check your email and code, then try again. No order was created." }
        }
    }
}
