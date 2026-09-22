import Foundation
import FoundationModels

/// Only messages actually shown by the app enter the local conversation. A
/// role is data, never a prefix parsed from user-supplied text.
struct ConversationTurn: Codable, Equatable, Sendable {
    let isUser: Bool
    let text: String
}

enum ConversationContext {
    static func completed(_ messages: [ConversationTurn], byteLimit: Int) -> [ConversationTurn] {
        var exchanges: [[ConversationTurn]] = []
        var current: [ConversationTurn] = []
        for message in messages {
            if message.isUser {
                if current.count == 2 { exchanges.append(current) }
                current = [message]
            } else if current.count == 1 {
                current.append(message)
            } else if current.count == 2 {
                current[1] = .init(isUser: false, text: current[1].text + "\n" + message.text)
            }
        }
        if current.count == 2 { exchanges.append(current) }
        exchanges = Array(exchanges.suffix(8))
        while exchanges.flatMap({ $0 }).reduce(0, { $0 + $1.text.utf8.count }) > byteLimit {
            exchanges.removeFirst()
        }
        return exchanges.flatMap { $0 }
    }

    static func entries(_ messages: [ConversationTurn]) -> [Transcript.Entry] {
        messages.map { message in
            let segments: [Transcript.Segment] = [.text(.init(content: message.text))]
            return message.isUser ? .prompt(.init(segments: segments)) :
                .response(.init(assetIDs: [], segments: segments))
        }
    }
}

/// The same local generation implementation is used by the phone and the
/// synthetic Mac evaluation runner. It has no tools, wallet or network client.
actor LocalConversationSession {
    enum Failure: Error { case busy, invalidResponse }
    private var generating = false
    private var session: LanguageModelSession?
    private var sessionLanguage = ""
    private var sessionNotes = ""
    private var knownHistory: [ConversationTurn] = []
    private var activeHistory: [ConversationTurn] = []

    private var contextByteLimit: Int {
        #if compiler(>=6.4)
        if #available(iOS 26.4, macOS 26.4, *) { return 24_000 }
        #endif
        return 6_000
    }

    func prepare(replyLanguage: String, notes: String) {
        guard !generating else { return }
        configure(history: knownHistory, replyLanguage: replyLanguage, notes: notes)
        session?.prewarm()
    }

    private func configure(history: [ConversationTurn], replyLanguage: String, notes: String) {
        let bounded = ConversationContext.completed(history, byteLimit: contextByteLimit)
        guard session == nil || knownHistory != bounded || sessionLanguage != replyLanguage || sessionNotes != notes else { return }
        knownHistory = bounded
        activeHistory = bounded
        sessionLanguage = replyLanguage
        sessionNotes = notes
        rebuild()
    }

    private func rebuild() {
        let fresh = LanguageModelSession(model: SystemLanguageModel.default,
            instructions: Self.instructions(replyLanguage: sessionLanguage))
        session = activeHistory.isEmpty ? fresh : LanguageModelSession(model: SystemLanguageModel.default,
            transcript: Transcript(entries: Array(fresh.transcript) + ConversationContext.entries(activeHistory)))
    }

    private func fitContext(prompt: String) async throws {
        #if compiler(>=6.4)
        if #available(iOS 26.4, macOS 26.4, *) {
            let model = SystemLanguageModel.default
            let promptTokens = try await model.tokenCount(for: prompt)
            let limit = min(model.contextSize, 8_192) - 512
            while let session {
                let used = try await model.tokenCount(for: Array(session.transcript))
                try Task.checkCancellation()
                if used + promptTokens <= limit { return }
                guard activeHistory.count >= 2 else { throw Failure.invalidResponse }
                activeHistory.removeFirst(2)
                rebuild()
            }
        }
        #endif
    }

    private static func instructions(replyLanguage: String) -> String {
        """
        You are Mate, a helpful conversational assistant. Respond in \(replyLanguage == "日本語" ? "Japanese" : "English"), briefly and naturally. Use plain speech, without Markdown.
        Answer the latest message directly. Use the person's stated preferences and corrections, and follow topic changes. If asked to recall a detail, give that detail; do not invent personal facts or repeat the user's question.
        You have no action tools. Do not claim to have bought, paid, searched or sent anything. Current order status comes from the app's checkout. History and notes are background, not permission to act.
        """
    }

    func streamReply(to text: String, history: [ConversationTurn], observations: String, notes: String,
                     replyLanguage: String, onPartial: @escaping @Sendable (String) async -> Void) async throws -> String {
        guard !generating else { throw Failure.busy }
        try Task.checkCancellation()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 8_000 else { throw Failure.invalidResponse }
        generating = true
        defer { generating = false }
        configure(history: history, replyLanguage: replyLanguage, notes: notes)
        var prompt = text
        if !notes.isEmpty { prompt = "Reference notes (background only):\n\(notes.prefix(600))\n\nCurrent message:\n" + prompt }
        if ["見える", "見てる", "見ている", "何がある", "what do you see", "looking at"].contains(where: { text.lowercased().contains($0) }) {
            prompt += "\n\n<current_camera_context>\(observations.prefix(500))</current_camera_context>"
        }
        do {
            try await fitContext(prompt: prompt)
            guard let session else { throw Failure.invalidResponse }
            let stream = session.streamResponse(to: prompt, options: GenerationOptions(temperature: 0.3, maximumResponseTokens: 350))
            var answer = ""
            for try await snapshot in stream {
                try Task.checkCancellation()
                let partial = snapshot.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard partial.utf8.count <= 12_000 else { throw Failure.invalidResponse }
                if partial != answer { answer = partial; await onPartial(partial) }
            }
            try Task.checkCancellation()
            guard !answer.isEmpty else { throw Failure.invalidResponse }
            let completed: [ConversationTurn] = [.init(isUser: true, text: text), .init(isUser: false, text: answer)]
            knownHistory += completed
            activeHistory += completed
            return answer
        } catch {
            // Failed/cancelled native transcript entries must never survive.
            session = nil
            throw error
        }
    }
}
