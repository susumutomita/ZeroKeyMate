import Foundation

/// A rule change proposed in conversation. Only a deterministic parse of the spoken
/// text, never the language model's own judgement, produces these fields; the caller
/// still routes them through the existing Rules approval screen and signature.
public struct RuleProposal: Equatable, Sendable {
    public let budgetUnits: UInt64
    public let translation: Bool
    public let summary: Bool
    public let hours: Int?
    public let unsupportedService: String?
    public init(budgetUnits: UInt64, translation: Bool, summary: Bool, hours: Int?, unsupportedService: String?) {
        self.budgetUnits = budgetUnits; self.translation = translation; self.summary = summary
        self.hours = hours; self.unsupportedService = unsupportedService
    }
}

/// Deterministic routing for spoken usage, revocation and rule-change requests.
/// This never itself changes a budget, revokes a mandate or discloses anything;
/// it only decides which existing approval screen a conversation turn should open.
public enum ConversationRouter {
    public static func isUsageStatusRequest(_ text: String) -> Bool {
        matches(text, phrases: [
            "いくらつかった", "いくらつかいましたか", "しようじょうきょう", "りようじょうきょう", "りようじょうきょうをおしえて",
            "のこりのよさん", "ざんだかはいくら", "いまいくらつかった",
            "howmuchhaveispent", "howmuchdidispend", "spendingstatus", "usagestatus", "howmuchhaveiused", "whatsmybalance",
        ])
    }
    public static func isRevokeRequest(_ text: String) -> Bool {
        matches(text, phrases: [
            "いにんをとりけして", "いにんをかいじょして", "けんげんをとりけして", "まんでーとをとりけして", "まんでーとをかいじょして",
            "revokethemandate", "revokemymandate", "cancelthemandate", "stopthemandate", "revokemandate", "revokeaccess",
        ])
    }
    /// Non-nil only when the message names an explicit USDC amount, so ordinary
    /// numbers in unrelated conversation never open the rules screen.
    public static func ruleProposal(from text: String, now: Date = Date(), timeZone: TimeZone = .current) -> RuleProposal? {
        guard let budgetUnits = extractBudgetUnits(text) else { return nil }
        let value = text.lowercased()
        let translation = ["翻訳", "translate", "translation"].contains { value.contains($0) }
        let summary = ["要約", "summary", "summarize", "summarise"].contains { value.contains($0) }
        let unsupported = ["調査", "検索", "research", "search", "購入", "buy", "shopping", "ショッピング"].first { value.contains($0) }
        return RuleProposal(budgetUnits: budgetUnits, translation: translation, summary: summary,
                             hours: extractHours(text, now: now, timeZone: timeZone), unsupportedService: unsupported)
    }
    private static func matches(_ text: String, phrases: [String]) -> Bool {
        let normalized = normalize(text)
        return phrases.contains { normalized.contains(normalize($0)) }
    }
    private static func normalize(_ text: String) -> String {
        text.lowercased().unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.punctuationCharacters.contains($0)
        }.map(String.init).joined()
    }
    private static func extractBudgetUnits(_ text: String) -> UInt64? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d+(?:\.\d{1,6})?)\s*usdc"#, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range), let numberRange = Range(match.range(at: 1), in: text) else { return nil }
        return try? TokenAmount(decimal: String(text[numberRange])).units
    }
    /// "Today"/"tonight" become an absolute expiry in the device's own time zone;
    /// any other phrasing leaves the caller's own default hours untouched.
    private static func extractHours(_ text: String, now: Date, timeZone: TimeZone) -> Int? {
        let value = text.lowercased()
        guard ["今日", "今夜", "今日中", "today", "tonight"].contains(where: { value.contains($0) }) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let midnight = calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0, second: 0),
                                                matchingPolicy: .nextTime) else { return nil }
        let seconds = midnight.timeIntervalSince(now)
        guard seconds > 0 else { return nil }
        return min(24, max(1, Int((seconds / 3600).rounded(.up))))
    }
}
