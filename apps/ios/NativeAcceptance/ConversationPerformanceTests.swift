import Foundation
import MateCore
import XCTest
@testable import ZeroKeyMate

private actor ConversationTiming {
    private let started=ContinuousClock.now
    private var firstText:Duration?
    private var firstSentence:Duration?
    private var spoken=SpokenTextBuffer()
    func receive(_ text:String) {
        if firstText==nil,!text.isEmpty {firstText=started.duration(to:.now)}
        if !spoken.consume(text).isEmpty,firstSentence==nil {firstSentence=started.duration(to:.now)}
    }
    func report() -> String {
        "first text: \(firstText?.description ?? "none"); first speakable sentence: \(firstSentence?.description ?? "only on final"); complete: \(started.duration(to:.now))"
    }
}

@MainActor
final class ConversationPerformanceTests:XCTestCase {
    func testPhysicalModelRecallAndStreamingTimings() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("This fixture measures the physical on-device model, not the simulator")
        #else
        let service=ConversationService()
        if let reason=await service.availability(){throw XCTSkip(reason)}
        let prompts=[
            "覚えてね。私の望遠鏡の名前はクモです。",
            "今日は空が晴れています。",
            "散歩は夕方に行く予定です。",
            "帰ったら紅茶を飲みます。",
            "明日は本を読みたいです。",
            "今は少しだけ休憩しています。",
            "私の望遠鏡の名前を覚えてる？"
        ]
        var history=""
        var lines=["OS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
                   "Thermal state: \(ProcessInfo.processInfo.thermalState.rawValue)",
                   "Model: SystemLanguageModel.default; fixed synthetic text only; no audio or payment"]
        defer {
            let attachment=XCTAttachment(string:lines.joined(separator:"\n\n"))
            attachment.name="on-device-conversation-timings";attachment.lifetime = .keepAlways;add(attachment)
        }
        for (index,prompt) in prompts.enumerated() {
            await service.prepare(replyLanguage:"日本語",notes:"")
            let timing=ConversationTiming()
            let reply=try await service.streamReply(to:prompt,history:history,observations:"",notes:"",replyLanguage:"日本語",
                onPartial:{await timing.receive($0)})
            lines.append("Turn \(index+1): \(prompt)\n\(reply.text)\n\(await timing.report())")
            history += "\nUser: \(prompt)\nMate: \(reply.text)"
            XCTAssertNil(reply.service)
            XCTAssertTrue(reply.disclosure.isEmpty)
            if index==4 || index==5 {XCTAssertFalse(reply.text.contains("クモ"),"An unrelated new topic must not be redirected to the telescope: \(reply.text)")}
            if index==prompts.count-1 {XCTAssertTrue(reply.text.contains("クモ") || reply.text.contains("くも"),reply.text)}
        }
        #endif
    }
}
