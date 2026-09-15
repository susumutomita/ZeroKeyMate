import Foundation

/// Converts cumulative model snapshots into complete spoken sentences. Keeps
/// unfinished words/numbers until the next snapshot and never repeats a prefix.
public struct SpokenTextBuffer: Sendable {
    private var emitted = ""
    public init() {}

    public mutating func consume(_ snapshot: String, final: Bool = false) -> [String] {
        guard snapshot.hasPrefix(emitted) else { return [] }
        var chunks: [String] = []
        var start = snapshot.index(snapshot.startIndex, offsetBy: emitted.count)
        var cursor = start
        while cursor < snapshot.endIndex {
            let character = snapshot[cursor]
            let next = snapshot.index(after: cursor)
            let sentenceEnd = "。！？!?\n".contains(character) ||
                (character == "." && next < snapshot.endIndex && snapshot[next].isWhitespace)
            if sentenceEnd {
                let text = String(snapshot[start..<next]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { chunks.append(text) }
                emitted = String(snapshot[..<next])
                start = next
            }
            cursor = next
        }
        if final {
            let tail = String(snapshot[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty { chunks.append(tail) }
            emitted = snapshot
        }
        return chunks
    }
}
