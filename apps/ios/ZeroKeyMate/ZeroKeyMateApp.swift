import SwiftUI

@main
struct ZeroKeyMateApp:App {
    @AppStorage(L10n.preferenceKey) private var language = AppLanguage.english.rawValue
    var body:some Scene {
        WindowGroup{content.environment(\.locale,Locale(identifier:language)).preferredColorScheme(.light)}
    }
    @ViewBuilder private var content: some View {
#if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-mate-card-entry-ui-check") {
            SignaturePINEntryTestScreen()
        } else { MateView() }
#else
        MateView()
#endif
    }
}
