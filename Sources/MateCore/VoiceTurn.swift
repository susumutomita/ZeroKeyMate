import Foundation

/// Bounds one explicitly started recognition turn. Time is supplied by the caller
/// so silence and duplicate-final behavior can be checked without a microphone.
public struct VoiceTurn: Sendable {
    public enum Outcome: Equatable, Sendable { case waiting, submit(String), silence }
    private let startedAt: TimeInterval
    private var changedAt: TimeInterval
    private var text = ""
    private var ended = false
    private let usesAudioActivity: Bool
    private var lastAudioActivity: TimeInterval?
    public init(now: TimeInterval, usesAudioActivity: Bool = false) {
        startedAt = now; changedAt = now; self.usesAudioActivity = usesAudioActivity
    }
    public mutating func noteAudioActivity(now: TimeInterval) {
        guard !ended else { return }
        lastAudioActivity = now
    }
    public mutating func update(_ value: String, now: TimeInterval, final: Bool = false) -> Outcome {
        guard !ended else { return .waiting }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != text { text = trimmed; changedAt = now }
        return poll(now: now, final: final)
    }
    public mutating func poll(now: TimeInterval, final: Bool = false) -> Outcome {
        guard !ended else { return .waiting }
        let quiet: Bool
        if usesAudioActivity, let lastAudioActivity {
            // Recognition can stall while the person is still talking. Require
            // both acoustic quiet and a short stable transcription interval.
            quiet = now - lastAudioActivity >= 0.9 && now - changedAt >= 0.3
        } else { quiet = now - changedAt >= 1.2 }
        let complete = final || now - startedAt >= 60 ||
            (text.isEmpty ? now - startedAt >= 15 : quiet)
        guard complete else { return .waiting }
        ended = true
        return text.isEmpty ? .silence : .submit(text)
    }
}
