import Foundation

/// A cheap candidate filter, never an authorization. Candidate requests still
/// pass through the structured local planner and the existing approval checks.
public enum AgentTaskIntent {
    public static func needsPlanning(_ input: String) -> Bool {
        let text = input.lowercased()
        return ["translat", "summar", "sum up", "condense", "tl;dr", "tldr",
                "short version", "shorten", "brief", "overview", "gist", "recap",
                "put this", "say this", "how do you say",
                "in english", "in japanese", "into english", "into japanese",
                "訳", "要約", "まとめ", "短く", "一言で", "英語", "日本語",
                "どう言", "簡潔", "かいつま", "大意", "概略", "概要"]
            .contains { text.contains($0) }
    }
}
