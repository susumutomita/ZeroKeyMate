import Foundation
import XCTest
@testable import ZeroKeyMate

private actor SuspendedConversation:ConversationResponding {
    private var continuation:CheckedContinuation<ConversationReply,Error>?
    func availability() -> String? {nil}
    func reply(to text:String,history:String,observations:String,notes:String,replyLanguage:String) async throws -> ConversationReply {
        try await withCheckedThrowingContinuation{continuation=$0}
    }
    var waiting:Bool{continuation != nil}
    func complete() {continuation?.resume(returning:ConversationReply(text:"test reply",service:nil,disclosure:""));continuation=nil}
}

@MainActor
final class ConversationTests:XCTestCase {
    func testRealConversationSwitchesReplyLanguage() async throws {
        let service=ConversationService()
        if let reason=await service.availability(){throw XCTSkip(reason)}
        var history=""
        for (prompt,expected) in [("Hello, how are you?",AppLanguage.english),("今日は会議が長くて疲れた。",.japanese),("Can you answer in English now?",.english)] {
            let language=ConversationLanguage.detect(prompt,fallback:.japanese)
            XCTAssertEqual(language,expected)
            let response=try await service.reply(to:prompt,history:history,observations:"",notes:"",replyLanguage:language.name)
            let evidence=XCTAttachment(string:"User: \(prompt)\nMate: \(response.text)")
            evidence.name="real-language-switch";evidence.lifetime = .keepAlways;add(evidence)
            XCTAssertEqual(ConversationLanguage.detect(response.text,fallback:expected == .english ? .japanese:.english),expected,response.text)
            history += "\nUser: \(prompt)\nMate: \(response.text)"
        }
    }
    private func waitUntil(_ predicate:@escaping () async -> Bool) async throws {
        for _ in 0..<100 {
            if await predicate(){return}
            try await Task.sleep(for:.milliseconds(10))
        }
        XCTFail("Conversation state did not settle")
    }
    func testReadingConversationAndOpeningControlsDoNotDiscardPendingReply() async throws {
        let service=SuspendedConversation()
        let model=CompanionModel(conversation:service)
        model.readAloud=false
        XCTAssertTrue(model.sleeping)
        model.send("hello")
        try await waitUntil{await service.waiting}
        model.sheet = .controls
        XCTAssertTrue(model.thinking)
        model.sheet = .conversation
        XCTAssertTrue(model.thinking)
        await service.complete()
        try await waitUntil{!model.thinking}
        XCTAssertEqual(model.messages.last?.text,"test reply")
        XCTAssertNil(model.draft)
        model.rest()
    }
    func testSettingsAndBackgroundDiscardLateReplies() async throws {
        for background in [false,true] {
            let service=SuspendedConversation()
            let model=CompanionModel(conversation:service)
            model.readAloud=false
            model.send("hello")
            try await waitUntil{await service.waiting}
            if background{model.setForeground(false)}else{model.sheet = .settings}
            await service.complete()
            try await Task.sleep(for:.milliseconds(50))
            XCTAssertFalse(model.thinking)
            XCTAssertFalse(model.voiceSessionActive)
            XCTAssertEqual(model.messages.count,1,"Late reply must not be displayed or spoken")
            model.rest()
        }
    }
    func testRealJapaneseConversationRecallsContextAndDeclinesAmazonPurchase() async throws {
        let service=ConversationService()
        if let reason=await service.availability(){throw XCTSkip(reason)}
        var history=""
        var evidence:[String]=[]
        defer {
            let attachment=XCTAttachment(string:evidence.joined(separator:"\n\n"))
            attachment.name="real-model-conversation-fixtures";attachment.lifetime = .keepAlways
            add(attachment)
        }
        for prompt in ["覚えておいて。机の上のマグカップは青色です。","さっきのマグカップは何色だった？","Mac miniをAmazonで買って","今日は会議が長くて、ちょっと疲れた。","どうして疲れたって言ったか覚えてる？"] {
            let start=Date()
            let response=try await service.reply(to:prompt,history:history,
                observations:"No current camera observations. Do not claim to see.",notes:"",replyLanguage:"日本語")
            evidence.append("User: \(prompt)\nMate: \(response.text)\nElapsed ms: \(Int(Date().timeIntervalSince(start)*1000))")
            XCTAssertNil(response.service)
            XCTAssertTrue(response.disclosure.isEmpty)
            if prompt.contains("何色") {XCTAssertTrue(response.text.contains("青"),response.text)}
            if prompt.contains("Amazon") {
                XCTAssertTrue(["できません","できない","買えない","買えません","対応していません","未対応","行えません","行えない"].contains{response.text.contains($0)},response.text)
                XCTAssertFalse(["注文しました","購入しました","検索しました"].contains{response.text.contains($0)},response.text)
                XCTAssertTrue(["用途","使","メモリ","予算","構成"].contains{response.text.contains($0)},response.text)
            }
            if prompt.contains("どうして疲れた") {XCTAssertTrue(response.text.contains("会議"),response.text)}
            history += "\nUser: \(prompt)\nMate: \(response.text)"
        }
    }
}
