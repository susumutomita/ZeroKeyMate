import Foundation

enum AppLanguage:String,CaseIterable,Identifiable {
    case english = "en", japanese = "ja"
    var id:String{rawValue}
    var name:String{self == .english ? "English":"日本語"}
    var speechLocale:String{self == .english ? "en-US":"ja-JP"}
}

enum L10n {
    // Start the companion experience in English, including installations with a
    // Japanese preference left by earlier development builds. Subsequent choices persist.
    static let preferenceKey="mate-companion-language"
    static let speechPreferenceKey="mate-spoken-language"
    static var speechLanguage:AppLanguage {
        AppLanguage(rawValue:UserDefaults.standard.string(forKey:speechPreferenceKey) ?? "ja") ?? .japanese
    }
    static var language:AppLanguage {
        language(in:.standard)
    }
    static func language(in defaults:UserDefaults)->AppLanguage {
        AppLanguage(rawValue:defaults.string(forKey:preferenceKey) ?? "en") ?? .english
    }
    static func text(_ key:String,language:AppLanguage? = nil) -> String {
        let selected=language ?? self.language
        guard let path=Bundle.main.path(forResource:selected.rawValue,ofType:"lproj"),let bundle=Bundle(path:path) else{return key}
        let translated=bundle.localizedString(forKey:key,value:key,table:"Localizable")
        if translated != key{return translated}
        // Preflight errors are composed of two independently localized messages.
        let prefix="No proof generated. "
        if key.hasPrefix(prefix),key.count>prefix.count{return text(prefix,language:selected)+text(String(key.dropFirst(prefix.count)),language:selected)}
        return key
    }
    static func format(_ key:String,_ arguments:CVarArg...) -> String {
        String(format:text(key),locale:Locale(identifier:language.rawValue),arguments:arguments)
    }
}
