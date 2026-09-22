import Foundation

/// Small, literal conversational facts, derived from visible user messages.
/// No inferred identity, persistence, model-generated facts or action authority.
enum ConversationMemory {
    private struct Facts {
        var name: String?
        var preferred: String?
        var disliked: String?
    }

    static func reply(to input: String, history: [ConversationTurn], language: String) -> String? {
        guard !PurchaseConversation.isLanguageTask(input) else { return nil }
        let japanese = language == "日本語"
        if let name = nameDeclaration(input) {
            return japanese ? "\(name)さんですね。" : "Nice to meet you, \(name)."
        }
        if let preference = preferenceDeclaration(input) {
            return japanese ? "\(preference.1)が好きで、\(preference.0)は苦手なんですね。" :
                "You prefer \(preference.1) and don't like \(preference.0)."
        }
        var facts = Facts()
        for message in ConversationContext.completed(history, byteLimit: 24_000) where message.isUser {
            if let name = nameDeclaration(message.text) { facts.name = name }
            if let preference = preferenceDeclaration(message.text) {
                facts.disliked = preference.0; facts.preferred = preference.1
            }
        }
        let nameQuestion = #"^(?:(?:私|僕|わたし|ぼく)の名前[、,\s]*(?:覚えて(?:る|いますか|いる)|は(?:何|なん)(?:だっけ|ですか)?)|do you remember my name|what(?:'s| is) my name)[？?。.!\s]*$"#
        if matches(nameQuestion, input) != nil {
            guard let name = facts.name else {
                return japanese ? "最近の会話には、あなたの名前がまだ残っていません。" :
                    "I don't have your name in the recent conversation."
            }
            return japanese ? "\(name)さんです。" : "Your name is \(name)."
        }
        let choices = matches(#"^(?:私には|僕には|わたしには)?(.{1,30}?)と(.{1,30}?)の?ど(?:っち|ちら)が(?:いい|良い)[？?。.!\s]*$"#, input) ??
            matches(#"^which should i (?:have|choose),?\s+(.{1,30}?) or (.{1,30}?)[?.!\s]*$"#, input)
        if let choices, choices.count == 2, let preferred = facts.preferred, let disliked = facts.disliked,
           Set(choices.map(normalize)) == Set([normalize(preferred), normalize(disliked)]), normalize(preferred) != normalize(disliked) {
            return japanese ? "\(preferred)が好きと話していたので、\(preferred)がよさそうです。" :
                "You said you prefer \(preferred), so I'd suggest \(preferred)."
        }
        return nil
    }

    private static func nameDeclaration(_ text: String) -> String? {
        let value = text.replacingOccurrences(of: #"^(?:訂正[、。\s]*|correction[: ,]+)"#, with: "", options: [.regularExpression, .caseInsensitive])
        let captured = matches(#"^(?:私|僕|わたし|ぼく)の名前は([^「」『』\"\n。！？!?]{1,40}?)(?:です|だよ|だ)[。.!\s]*(?:この会話の間だけ覚えてね[。.!\s]*)?$"#, value) ??
            matches(#"^my name is ([\p{L}\p{M} '-]{1,40}?)[.!\s]*(?:remember (?:it|that) for this conversation[.!\s]*)?$"#, value)
        return captured?.first
    }
    private static func preferenceDeclaration(_ text: String) -> (String, String)? {
        let captured = matches(#"^([^「」『』\"\n。！？!?]{1,30}?)は苦手(?:なので|で)[、\s]*([^「」『』\"\n。！？!?]{1,30}?)が好き(?:です|だよ|だ)?[。.!\s]*$"#, text) ??
            matches(#"^i (?:dislike|don't like) ([\p{L}\p{M} '-]{1,30}?) and (?:prefer|like) ([\p{L}\p{M} '-]{1,30}?)[.!\s]*$"#, text)
        guard let captured, captured.count == 2 else { return nil }
        return (captured[0], captured[1])
    }
    private static func normalize(_ text: String) -> String { text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
    private static func matches(_ pattern: String, _ text: String) -> [String]? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { return nil }
        return (1..<match.numberOfRanges).compactMap { index in
            Range(match.range(at: index), in: value).map { String(value[$0]).trimmingCharacters(in: .whitespacesAndNewlines) }
        }
    }
}
