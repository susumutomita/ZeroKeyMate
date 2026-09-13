import SwiftUI
import MateCore

struct ShopPurchaseSheet: View {
    @ObservedObject var model: CompanionModel
    @ObservedObject var wallet: WalletService
    @StateObject private var checkout = ShopCheckout()
    @State private var pin = ""
    // Keep the destination across the temporary checking phase when the user
    // returns from Mail. The one-use code remains local to the child view.
    @State private var buyerEmail = ""
    @State private var buyerCodeSentTo: String?
    @FocusState private var pinFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    private var heading: String {
        switch checkout.phase {
        case .initial,.checking: return "Opening the store"
        case .review: return "Let Mate get your beer"
        case .funding: return "Add free test USDC"
        case .card: return "Confirm you're 20 or older"
        case .preparingCard: return "Preparing the card scanner"
        case .readingCard: return "Hold your card to the phone"
        case .proving: return "Your phone is making the proof"
        case .verifying: return "The store is checking your proof"
        case .paymentApproval: return "Approve the exact payment"
        case .paying: return "Mate is paying the store"
        case .pending: return "Checking your payment"
        case .complete: return "Your test purchase is complete"
        case .expired: return "The payment window closed"
        case .unavailable: return "The store is not ready yet"
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center, spacing: 20) {
                    Image(systemName: checkout.phase == .complete ? "checkmark.seal.fill" : "mug.fill")
                        .font(.system(size: 48)).foregroundStyle(checkout.phase == .complete ? Color.green : Color.orange)
                        .frame(width: 88, height: 100).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Mate Lager").font(.title2.bold())
                        Text("One bottle · 330 ml").foregroundStyle(.secondary)
                        Text("0.10 test USDC").font(.headline)
                    }
                }
                Text(L10n.text(heading)).font(.title2.bold()).accessibilityIdentifier("shop-phase")
                if let url = checkout.storeURL {
                    Link(destination: url) { Label(url.host ?? "Store", systemImage: "arrow.up.right") }.font(.subheadline)
                }
                if let message = checkout.message {
                    Text(L10n.text(message)).foregroundStyle(.secondary).accessibilityIdentifier("shop-message")
                }
                switch checkout.phase {
                case .review:
                    Text("Mate will place this order, ask you to tap your My Number card, and prove your age on this phone. You'll approve the exact test payment with Face ID or your device passcode.")
                    privacy
                    if wallet.ownerAddress == nil {
                        ShopWalletConnection(wallet: wallet, email: $buyerEmail, sentTo: $buyerCodeSentTo)
                    } else {
                        Button("Start this order · 0.10 test USDC") { checkout.startOrder(wallet: wallet) }
                            .buttonStyle(.borderedProminent).accessibilityIdentifier("shop-start-order")
                    }
                case .funding:
                    Text("Your buyer wallet needs 0.10 test USDC on Arc Testnet. The store pays the network fee. No order has been created yet.")
                    if let address = checkout.fundingAddress {
                        Text(address).font(.footnote.monospaced()).textSelection(.enabled)
                        ShareLink(item: address) { Label("Share buyer address", systemImage: "square.and.arrow.up") }
                    }
                    Link("Get free test USDC from Circle", destination: URL(string: "https://faucet.circle.com/")!)
                    Text("Choose Arc Testnet and paste this buyer address. Return here after the faucet transfer.").foregroundStyle(.secondary)
                    Button("Check funds and start this order") { checkout.startOrder(wallet: wallet) }
                        .buttonStyle(.borderedProminent).disabled(checkout.busy)
                case .card:
                    Text("Use the signature PIN: 6–16 uppercase letters and numbers. This is different from the four-digit card PIN.")
                    SecureField("Signature PIN", text: $pin)
                        // This card credential is entered for this operation;
                        // it is not a website password to save or fill.
                        .textContentType(.oneTimeCode).privacySensitive()
                        .textInputAutocapitalization(.characters).autocorrectionDisabled().keyboardType(.asciiCapable)
                        .focused($pinFocused).submitLabel(.go)
                        .onSubmit { startCardRead() }
                        .textFieldStyle(.roundedBorder).accessibilityIdentifier("shop-signature-pin")
                    if !pin.isEmpty && !JPKICardReader.validSigningPIN(pin) {
                        Text("Use 6–16 characters: uppercase A–Z and 0–9. Then tap Start card scan.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    privacy
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
                    Text("The store has checked the age proof. This approves only this order, recipient and amount on Arc Testnet.")
                    Button("Approve 0.10 test USDC") { checkout.continuePayment(wallet: wallet) }
                        .buttonStyle(.borderedProminent).disabled(checkout.busy)
                case .pending:
                    if checkout.busy { ProgressView() }
                    Text("Keep this order. Closing this screen does not undo a payment already sent.").foregroundStyle(.secondary)
                    Button("Check the same order") { checkout.checkOrder() }.buttonStyle(.borderedProminent).disabled(checkout.busy)
                    if checkout.canRetryOriginal {
                        Button("Retry the original payment") { checkout.retryOriginalPayment() }.disabled(checkout.busy)
                    }
                case .complete:
                    Text("The store recorded your order and the test USDC payment was confirmed. Your card details stayed on this phone.")
                    if let hash = checkout.order?.paymentTransaction,
                       let url = URL(string: "https://testnet.arcscan.app/tx/" + hash) {
                        Link("View payment receipt", destination: url)
                    }
                    Button("Back to Mate") { model.finishShopConversation(); model.sheet = nil }.buttonStyle(.borderedProminent)
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
                    Button("Start a new order") { pin = ""; checkout.startNew() }.disabled(checkout.busy)
                }
                Text("Arc Testnet · No real money · No physical delivery")
                    .font(.footnote).foregroundStyle(.secondary)
            }.frame(maxWidth: 520, alignment: .leading).padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            if checkout.phase == .card {
                Button("Start card scan") { startCardRead() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .padding().background(.bar)
                    .disabled(!JPKICardReader.validSigningPIN(pin) || checkout.busy)
                    .accessibilityIdentifier("shop-tap-card")
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if pinFocused {
                    Spacer()
                    Button("Done") { pinFocused = false }
                }
            }
        }
        .navigationTitle("Mate's order").navigationBarTitleDisplayMode(.inline)
        .controlSize(.large)
        .task { checkout.load() }
        .onDisappear { pin = ""; buyerEmail = ""; buyerCodeSentTo = nil; checkout.cancel() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { pin = ""; checkout.cancel() }
            else if phase == .active { checkout.load() }
        }
    }
    private func startCardRead() {
        guard JPKICardReader.validSigningPIN(pin), !checkout.busy, checkout.phase == .card else { return }
        pinFocused = false
        let oneUse = pin
        pin = ""
        checkout.readCard(pin: oneUse, sensors: model.sensors)
    }
    private var privacy: some View {
        Label("Your name, address and birth date stay on this phone. The store receives the age proof, not your card.", systemImage: "lock.shield")
            .font(.subheadline).foregroundStyle(.secondary)
    }
    private var progressDetail: String {
        switch checkout.phase {
        case .preparingCard: return "Stopping the camera before opening the card scanner."
        case .readingCard: return "Keep the card against the top of your iPhone. Mate won't retry a rejected PIN."
        case .proving: return "The signed card data is being processed locally. Keep Mate open."
        case .verifying: return "Only the public proof is sent to the store."
        case .paying: return "Sending the approved authorization once, then checking the receipt."
        default: return "Checking the store and the on-device proof runtime."
        }
    }
}

/// Purchase-specific onboarding keeps the user in the order and does not
/// require a specialist API, policy vault, deposit approval or execution key.
private struct ShopWalletConnection: View {
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
            Text("Use your email to prepare a buyer wallet for this test purchase. Your card information is not shared with Privy.")
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
