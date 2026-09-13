import Foundation

/// A rule change proposed in conversation. Only a deterministic parse of the spoken
/// text, never the language model's own judgement, produces these fields; the caller
/// still routes them through the existing Rules approval screen and signature.
public struct RuleProposal: Equatable, Sendable {
    public let budgetUnits: UInt64
    public let translation: Bool
    public let summary: Bool
    public let validUntil: Date?
    public let unsupportedService: String?
    public init(budgetUnits: UInt64, translation: Bool, summary: Bool, validUntil: Date?, unsupportedService: String?) {
        self.budgetUnits = budgetUnits; self.translation = translation; self.summary = summary
        self.validUntil = validUntil; self.unsupportedService = unsupportedService
    }
}

/// Deterministic routing for spoken usage, revocation and rule-change requests.
/// This never itself changes a budget, revokes a mandate or discloses anything;
/// it only decides which existing approval screen a conversation turn should open.
public enum ConversationRouter {
    public static func isUsageStatusRequest(_ text: String) -> Bool {
        matches(text, phrases: [
            "いくら使った", "いくら使いましたか", "使用状況", "利用状況", "利用状況を教えて",
            "残りの予算", "残高はいくら", "今いくら使った",
            "howmuchhaveispent", "howmuchdidispend", "spendingstatus", "usagestatus", "howmuchhaveiused", "whatsmybalance",
        ])
    }
    public static func isRevokeRequest(_ text: String) -> Bool {
        matches(text, phrases: [
            "委任を取り消して", "委任を解除して", "権限を取り消して", "マンデートを取り消して", "マンデートを解除して",
            "revokethemandate", "revokemymandate", "cancelthemandate", "stopthemandate", "revokemandate", "revokeaccess",
        ])
    }
    /// Non-nil only when the message names an explicit USDC amount, so ordinary
    /// numbers in unrelated conversation never open the rules screen.
    public static func ruleProposal(from text: String, now: Date = Date(), timeZone: TimeZone = .current) -> RuleProposal? {
        guard isRuleInstruction(text), let budgetUnits = extractBudgetUnits(text) else { return nil }
        let value = text.lowercased()
        let translation = ["翻訳", "translate", "translation"].contains { value.contains($0) }
        let summary = ["要約", "summary", "summarize", "summarise"].contains { value.contains($0) }
        let unsupported = ["調査", "検索", "research", "search", "購入", "buy", "shopping", "ショッピング"].first { value.contains($0) }
        return RuleProposal(budgetUnits: budgetUnits, translation: translation, summary: summary,
                             validUntil: extractExpiry(text, now: now, timeZone: timeZone), unsupportedService: unsupported)
    }
    private static func matches(_ text: String, phrases: [String]) -> Bool {
        let normalized = normalize(text)
        let value = normalized.hasPrefix("please") ? String(normalized.dropFirst(6)) : normalized
        return phrases.contains { value == normalize($0) || value == normalize($0)+"today" || value == normalize($0)+"ください" }
    }
    private static func isRuleInstruction(_ text: String) -> Bool {
        let value = text.lowercased()
        // Only explicit permission or budget proposals. Quoted payloads and
        // instructions to translate/summarize them are handled by the task planner.
        guard !["\"", "「", "『", "“", "?", "？", "使わない", "許可しない", "don't", "do not"].contains(where: value.contains) else { return false }
        return value.range(of: #"^(?:今日は?|今夜は?)?\s*[0-9]+(?:\.[0-9]+)?\s*usdcまで[、,\s]*(?:翻訳|要約|調査|検索)(?:[\s\S]*)に使って(?:いい|よい|ください)[。！!]*$"#, options: .regularExpression) != nil ||
            value.range(of: #"^(?:(?:today|tonight)\s+)?(?:allow|set (?:a |the |my )?budget(?: of)?|up to)\s+[0-9]+(?:\.[0-9]+)?\s+usdc\s+for\s+(?:translation|summary|research)(?:[\s\S]*)$"#, options: .regularExpression) != nil ||
            value.range(of: #"^(?:翻訳|要約)(?:のみ|だけ)\s*[0-9]+(?:\.[0-9]+)?\s*usdcまで(?:[、,\s]*(?:今日中|今夜まで))?[。！!]*$"#, options: .regularExpression) != nil
    }
    private static func normalize(_ text: String) -> String {
        text.lowercased().unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.punctuationCharacters.contains($0)
        }.map(String.init).joined()
    }
    private static func extractBudgetUnits(_ text: String) -> UInt64? {
        guard let regex = try? NSRegularExpression(pattern: #"(?<![a-zA-Z0-9_.,+−-])(\d+(?:\.\d{1,6})?)\s*usdc(?![a-zA-Z0-9_])"#, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        guard matches.count == 1, let match = matches.first, let numberRange = Range(match.range(at: 1), in: text) else { return nil }
        return try? TokenAmount(decimal: String(text[numberRange])).units
    }
    /// "Today"/"tonight" pin the next local midnight, without rounding into tomorrow.
    /// Other phrasing requires the user to choose an expiry in the approval screen.
    private static func extractExpiry(_ text: String, now: Date, timeZone: TimeZone) -> Date? {
        let value = text.lowercased()
        guard ["今日", "今夜", "今日中", "today", "tonight"].contains(where: { value.contains($0) }) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let midnight = calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0, second: 0),
                                                matchingPolicy: .nextTime) else { return nil }
        let seconds = midnight.timeIntervalSince(now)
        guard seconds > 0 else { return nil }
        return midnight
    }
}
