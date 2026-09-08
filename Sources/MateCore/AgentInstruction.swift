import Foundation

public enum AgentInstruction {
    public static func hasUnsupportedTranslationTarget(_ input:String,source:String)->Bool {
        guard !source.isEmpty,let range=input.range(of:source) else{return true}
        let outside=String(input[..<range.lowerBound])+String(input[range.upperBound...])
        let patterns=[#"\b(?:into|to|in)\s+([a-z]+)\b"#, #"([一-龯ァ-ヶー]+語)(?:に|で|へ)"#]
        let allowed:Set<String>=["english","japanese","英語","日本語"]
        for pattern in patterns {
            guard let regex=try? NSRegularExpression(pattern:pattern,options:.caseInsensitive) else{return true}
            for match in regex.matches(in:outside,range:NSRange(outside.startIndex...,in:outside)) {
                if let found=Range(match.range(at:1),in:outside),!allowed.contains(outside[found].lowercased()){return true}
            }
        }
        return false
    }
    /// Model extraction is not spending consent. Unattended execution additionally
    /// requires an unambiguous direct instruction outside the text being processed.
    public static func isDirect(_ input:String,source:String,service:MateService)->Bool {
        guard !source.isEmpty,let range=input.range(of:source),
              input.range(of:source,range:range.upperBound..<input.endIndex)==nil else{return false}
        let outside=String(input[..<range.lowerBound])+String(input[range.upperBound...])
        let words=outside.lowercased().unicodeScalars.filter{!CharacterSet.punctuationCharacters.contains($0)}
        let control=String(String.UnicodeScalarView(words)).split(whereSeparator:{$0.isWhitespace}).joined(separator:" ")
        let patterns:[String]
        switch service {
        case .translation:
            patterns=[#"^(please )?translate( this| this text| the following)?( into| to)?( japanese| english)?( please)?$"#,
                      #"^(この文章|この文|これ)?を?(英訳|和訳|翻訳)(して|してください|お願いします|をお願いします)$"#,
                      #"^(この文章|この文|これ)?を?(英語|日本語)に(して|してください|訳して|訳してください)$"#]
        case .summary:
            patterns=[#"^(please )?summari[sz]e( this| this text| the following)?( please)?$"#,
                      #"^(この文章|この文|これ)?を?(要約)(して|してください|お願いします|をお願いします)$"#]
        }
        return patterns.contains{control.range(of:$0,options:.regularExpression) != nil}
    }
}
