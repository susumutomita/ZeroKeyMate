import Foundation

/// Pure text routing. This can recall an actual request, never authorize or report a payment.
enum PurchaseConversation {
    static func recall(input: String, history: [ConversationTurn], replyLanguage: String) -> String? {
        guard !isLanguageTask(input) else { return nil }
        let value=input.lowercased().trimmingCharacters(in:.whitespacesAndNewlines)
        let english = #"^(?:do you remember\s+)?what (?:did i ask you to|i asked you to) (?:buy|order|purchase)[?.!\s]*$"#
        let japanese = #"^(?:さっき|先ほど|前に)?(?:は|、|\s)*何を(?:買って|注文して|購入して)(?:って|と)(?:頼んだ|お願いした)(?:か|っけ|か覚えてる|か覚えている)?[。？！?\s]*$"#
        guard value.range(of:english,options:.regularExpression) != nil ||
              value.range(of:japanese,options:.regularExpression) != nil else { return nil }
        let previous=ConversationContext.completed(history,byteLimit:24_000)
            .last(where:{$0.isUser && !isLanguageTask($0.text) && isCurrentPurchaseRequest($0.text)})
        guard let previous else {
            return replyLanguage == "日本語" ? "この会話に残っている範囲では、購入の依頼は見つかりません。" :
                "I don't have a purchase request in the recent conversation."
        }
        return replyLanguage == "日本語" ? "「\(previous.text)」と頼まれました。" : "You asked: “\(previous.text)”"
    }

    static func isLanguageTask(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let english = #"^(?:please\s+)?(?:translate|summari[sz]e|explain|define|what does|what is the meaning|how do (?:you|i) say)\b"#
        return lower.range(of: english, options: .regularExpression) != nil ||
            ["翻訳", "英訳", "和訳", "要約", "意味を", "どういう意味", "英語にして", "日本語にして", "に訳して"].contains { lower.contains($0) }
    }
    static func isCurrentPurchaseRequest(_ text: String) -> Bool {
        let value = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        // A narrow proposal boundary complements model interpretation. Outside
        // these present-tense request forms, stay in conversation. This does
        // not authorize an order: the exact review and signing gates still apply.
        let english = #"^(?:(?:hey\s+)?mate[,\s]+)?(?:please[,\s]+)?(?:(?:buy|order|purchase|get|bring|fetch)\b|(?:can|could|would|will)\s+you\s+(?:please\s+)?(?:buy|order|purchase|get|bring|fetch)\b|(?:i want|i would like|i'd like)\s+you\s+to\s+(?:buy|order|purchase|get|bring|fetch)\b)"#
        let japanese = #"(?:買って(?:きて)?|購入して|注文して|買いたい|購入したい|注文したい)(?:ください|ほしい|くれる|くれない|くれませんか|もらえる|お願い|です|かな|な|よ|ね|[。！？.!?\s])*$"#
        let softVerb = #"^(?:(?:hey\s+)?mate[,\s]+)?(?:please[,\s]+)?(?:(?:can|could|would|will)\s+you\s+(?:please\s+)?|(?:i want|i would like|i'd like)\s+you\s+to\s+)?(?:get|bring|fetch)\b"#
        if value.range(of:softVerb,options:.regularExpression) != nil,
           value.range(of:#"\b(?:beers?|lagers?|waters?)\b"#,options:.regularExpression) == nil { return false }
        return value.range(of: english, options: .regularExpression) != nil ||
            value.range(of: japanese, options: .regularExpression) != nil
    }
}
