import Foundation

/// Matches a completed greeting locally; other standby speech is discarded.
public enum VoiceWakePhrase {
    public static func isRestCommand(_ text:String)->Bool {
        let normalized=text.lowercased().unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.punctuationCharacters.contains($0)
        }.map(String.init).joined()
        return ["おやすみ","おやすみなさい","お休み","お休みなさい","goodnight","goodnightmate"].contains(normalized)
    }
    public static func matches(_ text:String)->Bool {
        let greeting=text.lowercased().unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.punctuationCharacters.contains($0)
        }.map(String.init).joined()
        return ["こんにちは","こんにちわ","ハロー","hello","hellomate","こんにちはmate","こんにちはメイト"].contains(greeting)
    }
}
