import Foundation
import FoundationModels
import NaturalLanguage

private actor FirstChunk {
    let start = ContinuousClock.now
    var elapsed: Double?
    func receive(_ text: String) {
        if elapsed == nil, !text.isEmpty { elapsed = Self.seconds(start.duration(to: .now)) }
    }
    static func seconds(_ value: Duration) -> Double {
        Double(value.components.seconds) + Double(value.components.attoseconds) / 1e18
    }
}

@main struct ConversationEvaluation {
    struct Result: Codable {
        let responseSource: String
        let scenario: String
        let input: String
        let output: String
        let passed: Bool
        let firstTextSeconds: Double?
        let totalSeconds: Double
    }
    struct Report: Codable {
        let platform: String
        let os: String
        let model: String
        let syntheticOnly: Bool
        let status: String
        let results: [Result]
    }
    private static func isEnglish(_ text: String) -> Bool {
        // Short valid replies such as "Nice telescope!" are ambiguous to the
        // unconstrained recognizer; this suite exercises English/Japanese only.
        let recognizer=NLLanguageRecognizer()
        recognizer.languageConstraints=[.english,.japanese]
        recognizer.processString(text)
        return recognizer.dominantLanguage == .english
    }
    static func main() async {
        var results: [Result] = []
        var status = "failed"
        do {
            guard SystemLanguageModel.default.availability == .available else {
                throw EvaluationError.unavailable
            }
            guard SystemLanguageModel.default.supportsLocale(Locale(identifier: "ja_JP")),
                  SystemLanguageModel.default.supportsLocale(Locale(identifier: "en_US")) else {
                throw EvaluationError.unavailable
            }
            let session = LocalConversationSession()
            var history: [ConversationTurn] = []
            func turn(_ scenario: String, _ input: String, language: String = "日本語",
                      check: (String) -> Bool = { !$0.isEmpty }) async throws {
                await session.prepare(replyLanguage: language, notes: "")
                let timing = FirstChunk()
                let recalled=PurchaseConversation.recall(input:input,history:history,replyLanguage:language)
                let answer: String
                if let recalled { answer=recalled; await timing.receive(recalled) }
                else { answer = try await session.streamReply(to: input, history: history,
                    observations: "No camera observations are available.", notes: "", replyLanguage: language,
                    onPartial: { await timing.receive($0) }) }
                results.append(Result(responseSource: recalled == nil ? "local-model" : "quoted-request", scenario: scenario, input: input, output: answer, passed: check(answer) && !["マテ", "メイトの", "私のマグ", "私の犬", "my mug", "my dog"].contains(where:answer.contains),
                    firstTextSeconds: await timing.elapsed, totalSeconds: FirstChunk.seconds(timing.start.duration(to: .now))))
                history += [.init(isUser: true, text: input), .init(isUser: false, text: answer)]
            }
            try await turn("recall", "覚えてね。私のマグカップは青色です。")
            try await turn("recall", "マグカップは何色だった？", check: { $0.contains("青") })
            try await turn("correction", "訂正です。マグカップは青ではなく赤でした。")
            try await turn("correction", "正しいマグカップの色は？", check: { $0.contains("赤") })
            try await turn("topic-change", "今日は会議が長くて疲れた。", check: { !$0.contains("マグ") })
            try await turn("follow-up", "何で疲れたって言ったか覚えてる？", check: { $0.contains("会議") })

            // Inject the same typed roles supplied by the app after its routed
            // purchase refusal. This is synthetic context, never a real checkout.
            history += [.init(isUser: true, text: "Mac miniをAmazonで買って"),
                        .init(isUser: false, text: "Amazonでの購入は対応していません。購入も支払いも行っていません。")]
            try await turn("routed-context", "さっき何を買ってって頼んだ？", check: { $0.lowercased().contains("mac") })
            try await turn("language-switch", "Let's speak English. I named my telescope Nimbus.", language: "English",
                           check: { isEnglish($0) })
            try await turn("language-switch-recall", "望遠鏡の名前、何にしたか覚えてる？",
                           check: { ($0.lowercased().contains("nimbus") || $0.contains("ニンバス")) && !$0.contains("Amazon") })
            try await turn("ordinary-idiom", "Get some rest, Mate.", language: "English",
                           check: { !$0.lowercased().contains("purchase") && !$0.lowercased().contains("budget") && $0 != "Get some rest, Mate." })

            history = []
            try await turn("clear-context", "覚えて。私の犬の名前はポチです。")
            try await turn("clear-context", "犬の名前は何だった？", check: { $0.contains("ポチ") })
            status = results.allSatisfy(\.passed) ? "passed" : "failed"
        } catch {
            status = "unavailable-or-generation-error: \(error)"
        }
        let report = Report(platform: "Mac (not iPhone)", os: ProcessInfo.processInfo.operatingSystemVersionString,
            model: "SystemLanguageModel.default", syntheticOnly: true, status: status, results: results)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(report) { FileHandle.standardOutput.write(data) }
        if status != "passed" { exit(1) }
    }
    enum EvaluationError: Error { case unavailable }
}
