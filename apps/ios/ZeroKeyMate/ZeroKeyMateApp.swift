import SwiftUI

@main
struct ZeroKeyMateApp:App {
    @AppStorage(L10n.preferenceKey) private var language = AppLanguage.english.rawValue
    var body:some Scene {
        WindowGroup{MateView().environment(\.locale,Locale(identifier:language)).preferredColorScheme(.light)}
    }
}
