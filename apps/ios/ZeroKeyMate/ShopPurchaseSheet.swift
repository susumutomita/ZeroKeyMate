import SwiftUI
import MateCore

struct ShopPurchaseSheet: View {
    @ObservedObject var model: CompanionModel
    @ObservedObject var wallet: WalletService
    @StateObject private var checkout = ShopCheckout()
    @State private var pin = ""
    @Environment(\.scenePhase) private var scenePhase

    private var heading: String {
        switch checkout.phase {
        case .initial,.checking: return "Opening the store"
        case .review: return "Let Mate get your beer"
        case .card: return "Confirm you're 20 or older"
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
                Text(heading).font(.title2.bold()).accessibilityIdentifier("shop-phase")
                if let url = checkout.storeURL {
                    Link(destination: url) { Label(url.host ?? "Store", systemImage: "arrow.up.right") }.font(.subheadline)
                }
                if let message = checkout.message {
                    Text(message).foregroundStyle(.secondary).accessibilityIdentifier("shop-message")
                }
                switch checkout.phase {
                case .review:
                    Text("Mate will place this order, ask you to tap your My Number card, and prove your age on this phone. You'll approve the exact test payment with Face ID or your device passcode.")
                    privacy
                    if wallet.ownerAddress == nil {
                        Button("Connect wallet") { model.sheet = .wallet }.buttonStyle(.borderedProminent)
                    } else {
                        Button("Start this order · 0.10 test USDC") { checkout.startOrder(wallet: wallet) }
                            .buttonStyle(.borderedProminent).accessibilityIdentifier("shop-start-order")
                    }
                case .card:
                    Text("Use the signature PIN: 6–16 uppercase letters and numbers. This is different from the four-digit card PIN.")
                    SecureField("Signature PIN", text: $pin)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled().keyboardType(.asciiCapable)
                        .textFieldStyle(.roundedBorder).accessibilityIdentifier("shop-signature-pin")
                    Button("Tap card and continue") {
                        let oneUse = pin; pin = ""; checkout.readCard(pin: oneUse, wallet: wallet)
                    }.buttonStyle(.borderedProminent).disabled(!JPKICardReader.validSigningPIN(pin) || checkout.busy)
                        .accessibilityIdentifier("shop-tap-card")
                    privacy
                case .readingCard,.proving,.verifying,.paying,.checking,.initial:
                    ProgressView().controlSize(.large)
                    Text(progressDetail).foregroundStyle(.secondary)
                case .paymentApproval:
                    Text("The store has checked the age proof. This approves only this order, recipient and amount on Base Sepolia.")
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
                       let url = URL(string: "https://sepolia.basescan.org/tx/" + hash) {
                        Link("View payment receipt", destination: url)
                    }
                    Button("Back to Mate") { model.finishShopConversation(); model.sheet = nil }.buttonStyle(.borderedProminent)
                case .unavailable:
                    Text("You can close this screen. Mate hasn't completed a purchase.").foregroundStyle(.secondary)
                    Button("Check again") { checkout.retryAvailability() }.buttonStyle(.borderedProminent).disabled(checkout.busy)
                case .expired:
                    Text("The original authorization expired without being used. Mate checked the finalized network record; this order was not paid.")
                }
                if checkout.canStartNew {
                    Button("Start a new order") { pin = ""; checkout.startNew() }.disabled(checkout.busy)
                }
                Text("Base Sepolia testnet · No real money · No physical delivery")
                    .font(.footnote).foregroundStyle(.secondary)
            }.frame(maxWidth: 520, alignment: .leading).padding(24)
        }
        .navigationTitle("Mate's order").navigationBarTitleDisplayMode(.inline)
        .controlSize(.large)
        .task { checkout.load() }
        .onDisappear { pin = ""; checkout.cancel() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { pin = ""; checkout.cancel() }
            else if phase == .active { checkout.load() }
        }
    }
    private var privacy: some View {
        Label("Your name, address and birth date stay on this phone. The store receives the age proof, not your card.", systemImage: "lock.shield")
            .font(.subheadline).foregroundStyle(.secondary)
    }
    private var progressDetail: String {
        switch checkout.phase {
        case .readingCard: return "Keep the card against the top of your iPhone. Mate won't retry a rejected PIN."
        case .proving: return "The signed card data is being processed locally. Keep Mate open."
        case .verifying: return "Only the public proof is sent to the store."
        case .paying: return "Sending the approved authorization once, then checking the receipt."
        default: return "Checking the store and the on-device proof runtime."
        }
    }
}
