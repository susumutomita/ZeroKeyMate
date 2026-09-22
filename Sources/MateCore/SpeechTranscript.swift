import Foundation

/// SpeechAnalyzer finalizes audio ranges, not whole conversational turns.
/// A revised volatile range replaces its predecessor; it is never appended twice.
public struct SpeechTranscript: Sendable {
    private var committed = ""
    private var volatile = ""
    private var committedEnd: Double = -.infinity
    public var text: String { committed + volatile }
    public init() {}

    public mutating func update(_ text: String, start: Double, end: Double, isFinal: Bool) {
        guard start.isFinite, end.isFinite, end > start, start >= committedEnd else { return }
        if isFinal {
            committed += text
            committedEnd = end
            volatile = ""
        } else {
            volatile = text
        }
    }
}
