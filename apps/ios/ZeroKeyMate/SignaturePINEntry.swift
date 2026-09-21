import SwiftUI
import MateCore

/// Ephemeral form state only. Invalid input never reaches CoreNFC; a valid PIN
/// is handed off once and immediately removed from the editable form.
@MainActor final class SignaturePINEntry: ObservableObject {
    // Rewriting SecureField's binding during an edit can overwrite an in-flight
    // keystroke. Preserve the editable text; normalize only for validation and
    // the one-use handoff to the card.
    @Published var pin = ""
    // The card uses uppercase ASCII. Convert only a-z; never trim, transliterate
    // Unicode, drop characters, or change digits in a credential.
    static func uppercaseASCII(_ input: String) -> String {
        String(decoding: input.utf8.map { (97...122).contains($0) ? $0 - 32 : $0 }, as: UTF8.self)
    }
    @Published var feedback: String?
    @Published var focusRequested = false

    static func problem(_ input: String) -> String? {
        let pin = uppercaseASCII(input)
        if pin.isEmpty { return "Enter your signature password to start the scan." }
        if pin.count == 4, pin.utf8.allSatisfy({ (48...57).contains($0) }) {
            return "Use the 6–16 character signature password, not the four-digit PIN."
        }
        if !(6...16).contains(pin.count) { return "Your signature password needs 6–16 characters." }
        if !pin.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) }) {
            return "Use uppercase A–Z and numbers 0–9."
        }
        guard JPKICardReader.validSigningPIN(pin) else {
            return "Include both uppercase letters and numbers."
        }
        return nil
    }
    func submit(busy: Bool, ready: (String) -> Void) {
        guard !busy else { return }
        if let problem = Self.problem(pin) {
            feedback = problem; focusRequested = true
            return
        }
        let oneUse = Self.uppercaseASCII(pin)
        clear()
        ready(oneUse)
    }
    func clear() { pin = ""; feedback = nil; focusRequested = false }
}

struct SignaturePINField: View {
    @ObservedObject var entry: SignaturePINEntry
    let submit: () -> Void
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Signature password · 6–16 letters and numbers")
                .font(.subheadline).foregroundStyle(.secondary)
            SecureField("Signature password", text: $entry.pin)
                .textContentType(.oneTimeCode).privacySensitive()
                .textInputAutocapitalization(.characters).autocorrectionDisabled().keyboardType(.asciiCapable)
                .focused($focused).submitLabel(.go).onSubmit(submit)
                .textFieldStyle(.roundedBorder).accessibilityIdentifier("shop-signature-pin")
            if let feedback = entry.feedback {
                Text(L10n.text(feedback)).font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityIdentifier("shop-pin-feedback")
            }
        }
        .onChange(of: entry.pin) { _, pin in
            if entry.feedback != nil { entry.feedback = SignaturePINEntry.problem(pin) }
        }
        .onChange(of: entry.focusRequested) { _, requested in focused = requested }
        .onChange(of: focused) { _, focused in entry.focusRequested = focused }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if focused { Spacer(); Button("Done") { focused = false } }
            }
        }
    }
}

struct SignaturePINScanButton: View {
    let busy: Bool
    let submit: () -> Void
    var body: some View {
        Button(action: submit) {
            HStack {
                if busy { ProgressView() }
                Text(L10n.text(busy ? "One moment." : "Start card scan"))
            }.frame(maxWidth: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(.borderedProminent).controlSize(.large)
        .disabled(busy)
        .accessibilityIdentifier("shop-tap-card")
        .padding().background(.bar)
    }
}

#if DEBUG && targetEnvironment(simulator)
/// UI-test-only host for the exact production field and action. It never
/// creates checkout, wallet, camera or NFC services, and cannot run on iPhone.
struct SignaturePINEntryTestScreen: View {
    @StateObject private var entry = SignaturePINEntry()
    @State private var submissions = 0
    @Environment(\.scenePhase) private var scenePhase
    private func submit() { entry.submit(busy: false) { _ in submissions += 1 } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Card input test — no card or purchase")
                    SignaturePINField(entry: entry, submit: submit)
                    Text("Accepted inputs: \(submissions)").accessibilityIdentifier("accepted-inputs")
                }.padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) { SignaturePINScanButton(busy: false, submit: submit) }
            .navigationTitle("Card input test")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onDisappear { entry.clear() }
        .onChange(of: scenePhase) { _, phase in if phase == .background { entry.clear() } }
    }
}
#endif
