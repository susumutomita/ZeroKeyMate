import Foundation

/// Bounds one explicitly started recognition turn. Time is supplied by the caller
/// so silence and duplicate-final behavior can be checked without a microphone.
public struct VoiceTurn: Sendable {
    public enum Outcome: Equatable, Sendable { case waiting, submit(String), silence }
    private let startedAt: TimeInterval
    private var changedAt: TimeInterval
    private var text = ""
    private var ended = false
    public init(now: TimeInterval) { startedAt = now; changedAt = now }
    public mutating func update(_ value: String, now: TimeInterval, final: Bool = false) -> Outcome {
        guard !ended else { return .waiting }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != text { text = trimmed; changedAt = now }
        return poll(now: now, final: final)
    }
    public mutating func poll(now: TimeInterval, final: Bool = false) -> Outcome {
        guard !ended else { return .waiting }
        let complete = final || now - startedAt >= 60 ||
            (text.isEmpty ? now - startedAt >= 15 : now - changedAt >= 2)
        guard complete else { return .waiting }
        ended = true
        return text.isEmpty ? .silence : .submit(text)
    }
}
