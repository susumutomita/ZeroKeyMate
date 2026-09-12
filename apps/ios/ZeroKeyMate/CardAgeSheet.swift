import SwiftUI
import MateCore

/// Explicit card-read entry point for physical acceptance. This does not claim
/// government authentication or enable checkout before the credential verifier.
struct CardAgeSheet: View {
    @StateObject private var reader = MyNumberNFCService()
    @State private var pin = ""
    @State private var message: String?
    @State private var task: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Form {
            Section {
                Label("Your card stays with you", systemImage: "person.crop.rectangle")
                    .font(.title3.weight(.semibold))
                Text("Enter the four-digit card input-assistance PIN, then hold your card against the top of this iPhone. The PIN is used only for this read.")
                SecureField("Four-digit card PIN", text: $pin)
                    .keyboardType(.numberPad).textContentType(.none)
                    .accessibilityIdentifier("card-pin")
                    .disabled(reader.scanning)
                Button(reader.scanning ? "Reading card…" : "Read my card") {
                    message = nil
                    let submittedPIN = pin
                    pin = ""
                    task = Task { @MainActor in
                        do {
                            _ = try await reader.scan(pin: submittedPIN)
                            message = "Card read. No personal information was sent. Government signature verification is not connected yet, so checkout remains locked."
                        } catch {
                            message = errorMessage(error)
                        }
                    }
                }
                .disabled(reader.scanning || pin.utf8.count != 4 || !pin.utf8.allSatisfy { (48...57).contains($0) } || !reader.available)
                .accessibilityIdentifier("read-card")
                if reader.scanning {
                    ProgressView("Keep the card still")
                    Button("Cancel card reading", role: .cancel) { stop() }
                }
                if !reader.available { Text("Card reading requires an NFC-capable iPhone.") }
            }
            if let message {
                Section { Text(L10n.text(message)).accessibilityIdentifier("card-read-status") }
                    .accessibilityAddTraits(.updatesFrequently)
            }
            Section("What leaves this phone") {
                Text("Nothing from this card read. The PIN, card data and birth date are not saved or sent to a server.")
                Text("Reading a birth date alone does not prove identity or age to a shop. Checkout must wait for the signed credential and the age proof to be verified.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Age verification")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { stop() }
        .onChange(of: scenePhase) { _, phase in if phase == .background { stop() } }
    }

    private func stop() { pin = ""; task?.cancel(); reader.cancel(); task = nil }

    private func errorMessage(_ error: Error) -> String {
        if let cardError = error as? MyNumberCardError {
            switch cardError {
            case .invalidPIN: return "Enter exactly four digits."
            case .pinRejected: return "The PIN was rejected. Mate will not try it again automatically. Check your PIN before another attempt."
            case .pinBlocked: return "The card PIN is locked. No further attempt was made."
            default: return "The card could not be read. No personal information was sent."
            }
        }
        if error is CancellationError || (error as? CardScanError) == .cancelled {
            return "Card reading stopped. Nothing was sent."
        }
        return "The card could not be read. No personal information was sent."
    }
}
