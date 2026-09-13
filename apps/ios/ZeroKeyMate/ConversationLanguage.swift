import NaturalLanguage

enum ConversationLanguage {
    static func detect(_ text:String,fallback:AppLanguage)->AppLanguage {
        // Kana makes mixed Japanese/English product requests unambiguous.
        if text.unicodeScalars.contains(where:{(0x3040...0x30FF).contains(Int($0.value))}){return .japanese}
        let recognizer=NLLanguageRecognizer()
        recognizer.processString(text)
        switch recognizer.dominantLanguage {
        case .japanese:return .japanese
        case .english:return .english
        default:return fallback
        }
    }
}
