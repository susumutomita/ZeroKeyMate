import Foundation

enum AppLanguage:String,CaseIterable,Identifiable {
    case english = "en", japanese = "ja"
    var id:String{rawValue}
    var name:String{self == .english ? "English":"日本語"}
    var speechLocale:String{self == .english ? "en-US":"ja-JP"}
}

enum L10n {
    static let preferenceKey="mate-language"
    static var language:AppLanguage {
        AppLanguage(rawValue:UserDefaults.standard.string(forKey:preferenceKey) ?? "en") ?? .english
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
