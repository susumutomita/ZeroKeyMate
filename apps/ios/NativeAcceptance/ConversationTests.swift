import Foundation
import FoundationModels
import XCTest
@testable import ZeroKeyMate

private actor ChatOnlyPlanner:AgentPlanning {
    func request(from input:String) async throws -> AgentRequest? {nil}
}

private actor SuspendedConversation:ConversationResponding {
    private var continuation:CheckedContinuation<ConversationReply,Error>?
    func availability() -> String? {nil}
    func reply(to text:String,history:[ConversationTurn],observations:String,notes:String,replyLanguage:String) async throws -> ConversationReply {
        try await withCheckedThrowingContinuation{continuation=$0}
    }
    var waiting:Bool{continuation != nil}
    func complete() {continuation?.resume(returning:ConversationReply(text:"test reply",service:nil,disclosure:""));continuation=nil}
}

private actor StreamingConversation:ConversationResponding {
    private var continuation:CheckedContinuation<ConversationReply,Error>?
    private var partial:(@Sendable (String) async -> Void)?
    func availability()->String?{nil}
    func reply(to text:String,history:[ConversationTurn],observations:String,notes:String,replyLanguage:String) async throws -> ConversationReply {
        try await streamReply(to:text,history:history,observations:observations,notes:notes,replyLanguage:replyLanguage,onPartial:{_ in})
    }
    func streamReply(to text:String,history:[ConversationTurn],observations:String,notes:String,replyLanguage:String,
                     onPartial:@escaping @Sendable (String) async -> Void) async throws -> ConversationReply {
        partial=onPartial
        return try await withCheckedThrowingContinuation{continuation=$0}
    }
    var waiting:Bool{continuation != nil}
    func emit(_ text:String) async {await partial?(text)}
    func complete(){continuation?.resume(returning:ConversationReply(text:"Hello. How are you?",service:nil,disclosure:""));continuation=nil}
    func block(){continuation?.resume(throwing:ConversationFailure.responseBlocked);continuation=nil}
}

private actor BlockedThenSuccessfulConversation:ConversationResponding {
    private(set) var calls=0
    func availability()->String?{nil}
    func reply(to text:String,history:[ConversationTurn],observations:String,notes:String,replyLanguage:String) async throws -> ConversationReply {
        calls += 1
        if calls==1{throw ConversationFailure.responseBlocked}
        return ConversationReply(text:"Let's talk about your day.",service:nil,disclosure:"")
    }
}

private actor ContextRecordingConversation:ConversationResponding {
    private(set) var receivedHistory:[ConversationTurn]=[]
    private(set) var language=""
    func availability()->String?{nil}
    func reply(to text:String,history:[ConversationTurn],observations:String,notes:String,replyLanguage:String) async throws -> ConversationReply {
        receivedHistory=history;language=replyLanguage
        return ConversationReply(text:"Recorded reply",service:nil,disclosure:"")
    }
}

@MainActor
final class ConversationTests:XCTestCase {
    func testPurchaseRecallQuotesTheActualRequestWithoutInventingCompletion() async throws {
        let service=ConversationService()
        let request="Mac miniをAmazonで買って"
        let history:[ConversationTurn]=[.init(isUser:true,text:request),
            .init(isUser:false,text:"その購入は実行できません。")]
        for (input,language) in [("さっき何を買ってって頼んだ？","日本語"),("What did I ask you to buy?","English")] {
            let response=try await service.reply(to:input,history:history,observations:"",notes:"",replyLanguage:language)
            XCTAssertTrue(response.text.contains(request))
            XCTAssertFalse(response.text.contains("購入しました"))
            XCTAssertFalse(response.text.contains("completed"))
            XCTAssertNil(response.service)
        }
        XCTAssertNil(PurchaseConversation.recall(input:"Translate 'what did I ask you to buy?'",history:history,replyLanguage:"English"))
        XCTAssertNil(PurchaseConversation.recall(input:"Did my payment complete?",history:history,replyLanguage:"English"))
        let unknown=PurchaseConversation.recall(input:"What did I ask you to buy?",history:[],replyLanguage:"English")
        XCTAssertTrue(unknown?.contains("don't have")==true)
        let interrupted=PurchaseConversation.recall(input:"What did I ask you to buy?",history:[.init(isUser:true,text:request)],replyLanguage:"English")
        XCTAssertEqual(interrupted,unknown)
    }
    func testRoutedReplyIsVisibleToTheNextConversationTurn() async throws {
        let service=ContextRecordingConversation()
        let model=CompanionModel(conversation:service,planner:ChatOnlyPlanner())
        model.readAloud=false
        model.send("残りの予算")
        try await waitUntil{!model.thinking}
        let routed=try XCTUnwrap(model.messages.last?.text)
        XCTAssertTrue(routed.contains("復元"))
        model.send("それはどういう意味？")
        try await waitUntil{!model.thinking}
        let history=await service.receivedHistory
        XCTAssertEqual(history,[.init(isUser:true,text:"残りの予算"),.init(isUser:false,text:routed)])
        XCTAssertNil(model.draft)
        XCTAssertFalse(model.voice.listening)
        model.rest()
    }
    func testNumericFollowUpKeepsTheConversationLanguageAndClearRemovesHistory() async throws {
        let service=ContextRecordingConversation()
        let model=CompanionModel(conversation:service,planner:ChatOnlyPlanner())
        model.readAloud=false
        model.send("こんにちは")
        try await waitUntil{!model.thinking}
        model.send("123")
        try await waitUntil{!model.thinking}
        let language=await service.language
        XCTAssertEqual(language,"日本語")
        model.clearConversation()
        model.send("Hello again")
        try await waitUntil{!model.thinking}
        let history=await service.receivedHistory
        let nextLanguage=await service.language
        XCTAssertTrue(history.isEmpty)
        XCTAssertEqual(nextLanguage,"English")
        model.rest()
    }

    #if compiler(>=6.4)
    func testIOS27GuardrailErrorUsesTheSameRecovery() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Requires iOS 27 error types") }
        let context=LanguageModelError.GuardrailViolation(debugDescription:"Synthetic test context")
        XCTAssertEqual(ConversationFailure(modelError:LanguageModelError.guardrailViolation(context)),.responseBlocked)
        XCTAssertNil(ConversationFailure(modelError:LanguageModelError.contextSizeExceeded(.init(contextSize:4096,tokenCount:4097,debugDescription:"Synthetic overflow"))))
    }
    #endif
    func testOnlyTheGuardrailErrorGetsTheRephraseRecovery() {
        let context=LanguageModelSession.GenerationError.Context(debugDescription:"Synthetic test context")
        XCTAssertEqual(ConversationFailure(modelError:LanguageModelSession.GenerationError.guardrailViolation(context)),.responseBlocked)
        XCTAssertNil(ConversationFailure(modelError:LanguageModelSession.GenerationError.exceededContextWindowSize(context)))
        XCTAssertNil(ConversationFailure(modelError:CancellationError()))
        XCTAssertNil(ConversationFailure(modelError:ProductError.invalidResponse))
    }
    func testBlockedReplyKeepsMateAwakeAndWaitsForANewUserTurn() async throws {
        for (input,expected) in [("Hello.","Could you say it another way?"),("こんにちは。","別の言い方")] {
            let service=BlockedThenSuccessfulConversation()
            let model=CompanionModel(conversation:service,planner:ChatOnlyPlanner())
            model.readAloud=false
            model.send(input)
            try await waitUntil{!model.thinking}
            XCTAssertFalse(model.sleeping)
            XCTAssertNil(model.errorMessage)
            XCTAssertTrue(model.messages.last?.text.contains(expected)==true)
            XCTAssertTrue(model.streamingReply.isEmpty)
            XCTAssertFalse(model.voice.listening)
            XCTAssertFalse(model.sensors.captureRequested)
            XCTAssertNil(model.draft)
            let calls=await service.calls
            XCTAssertEqual(calls,1,"A blocked input must never be retried automatically")
            model.send("Let's talk about my day.")
            try await waitUntil{!model.thinking}
            XCTAssertEqual(model.messages.last?.text,"Let's talk about your day.")
            XCTAssertFalse(model.sleeping)
            model.rest()
        }
    }
    func testBlockedLateStreamCannotWakeMateOrRevivePartialText() async throws {
        for stop in 0..<3 {
            let service=StreamingConversation()
            let model=CompanionModel(conversation:service,planner:ChatOnlyPlanner())
            model.readAloud=false
            model.send("Hello.")
            try await waitUntil{await service.waiting}
            await service.emit("An unfinished response")
            if stop==0{model.rest()}
            else if stop==1{model.setForeground(false)}
            else{model.sheet = .settings}
            await service.block()
            try await Task.sleep(for:.milliseconds(40))
            XCTAssertEqual(model.messages.count,1)
            XCTAssertTrue(model.streamingReply.isEmpty)
            XCTAssertFalse(model.thinking)
            XCTAssertFalse(model.voice.speaking)
            XCTAssertFalse(model.voice.listening)
            XCTAssertFalse(model.sensors.captureRequested)
            model.rest()
        }
    }
    func testConversationCannotInventTheResultOfAnExplicitPurchase() async throws {
        // This boundary also works when the system model is unavailable.
        // Real catalogue purchases are handled before this chat-only service.
        let service=ConversationService()
        for (input,language,expected) in [
            ("Mac miniをAmazonで買って","日本語","実行できません"),
            ("Please buy a laptop on Amazon.","English","can't make that purchase")
        ] {
            let response=try await service.reply(to:input,history:[],observations:"",notes:"",replyLanguage:language)
            XCTAssertTrue(response.text.contains(expected),response.text)
            XCTAssertNil(response.service)
            XCTAssertFalse(response.text.contains("購入しました"))
            XCTAssertFalse(response.text.contains("completed"))
        }
        do {
            _=try await service.reply(to:"Buy "+String(repeating:"x",count:8_001),history:[],observations:"",notes:"",replyLanguage:"English")
            XCTFail("Overlong purchase text must still be rejected")
        } catch ProductError.invalidResponse {} catch {XCTFail("Unexpected error: \(error)")}
    }

    func testPartialReplyAppearsBeforeCompletionAndCommitsOnlyOnce() async throws {
        let service=StreamingConversation()
        let model=CompanionModel(conversation:service,planner:ChatOnlyPlanner())
        model.readAloud=false
        model.send("hello")
        try await waitUntil{await service.waiting}
        await service.emit("Hello.")
        XCTAssertTrue(model.thinking)
        XCTAssertEqual(model.streamingReply,"Hello.")
        XCTAssertEqual(model.messages.count,1)
        await service.emit("Hello. How are you?")
        await service.complete()
        try await waitUntil{!model.thinking}
        XCTAssertEqual(model.messages.map(\.text),["hello","Hello. How are you?"])
        XCTAssertTrue(model.streamingReply.isEmpty)
        XCTAssertNil(model.draft)
        model.rest()
    }
    func testInterruptedStreamCannotSpeakDisplayOrResumeFromLateChunks() async throws {
        for stop in 0..<3 {
            let service=StreamingConversation()
            let model=CompanionModel(conversation:service,planner:ChatOnlyPlanner())
            model.readAloud=false
            model.send("hello")
            try await waitUntil{await service.waiting}
            await service.emit("Hello.")
            if stop==0{_ = model.interruptReply()}
            else if stop==1{model.setForeground(false)}
            else{model.sheet = .settings}
            await service.emit("Hello. How are you?")
            await service.complete()
            try await Task.sleep(for:.milliseconds(30))
            XCTAssertTrue(model.streamingReply.isEmpty)
            XCTAssertEqual(model.messages.count,1)
            XCTAssertFalse(model.thinking)
            XCTAssertFalse(model.voice.speaking)
            XCTAssertFalse(model.voiceSessionActive)
            XCTAssertFalse(model.sensors.captureRequested)
            model.rest()
        }
    }
    func testStandMovementOffAndOutcomeDoNotStartSensors() {
        let model=CompanionModel(planner:ChatOnlyPlanner())
        let previous=model.sensors.standMovementEnabled
        defer{model.sensors.setStandMovementEnabled(previous);model.rest()}
        model.sensors.setStandMovementEnabled(false)
        model.wake()
        model.makeOutcomeFeedback()(.confirmed)
        XCTAssertEqual(model.lastOutcome,.confirmed)
        XCTAssertFalse(model.sensors.standMotionAllowed)
        XCTAssertFalse(model.sensors.captureRequested)
        XCTAssertFalse(model.sensors.reactionRunning)
        XCTAssertFalse(model.voice.listening)
        model.sheet = .disclosure
        XCTAssertEqual(model.activity,.approval)
        model.rest()
        XCTAssertEqual(model.activity,.resting)
    }
    func testOutcomeFeedbackCannotResumeAfterRestBackgroundOrNewInteraction() {
        for stop in 0..<3 {
            let model=CompanionModel(planner:ChatOnlyPlanner())
            model.sleeping=false
            let feedback=model.makeOutcomeFeedback()
            feedback(.confirmed)
            XCTAssertEqual(model.lastOutcome,.confirmed)
            if stop == 0 {model.rest()}
            else if stop == 1 {model.setForeground(false);model.setForeground(true)}
            else {model.sheet = .settings}
            model.sleeping=false // Even waking again must not revive the old result.
            feedback(.confirmed);feedback(.rejected)
            XCTAssertNil(model.lastOutcome)
            model.makeOutcomeFeedback()(.rejected)
            XCTAssertEqual(model.lastOutcome,.rejected)
            model.rest()
        }
    }
    func testRealConversationSwitchesReplyLanguage() async throws {
        try requirePhysicalModel()
        let service=ConversationService()
        if let reason=await service.availability(){throw XCTSkip(reason)}
        var history:[ConversationTurn]=[]
        for (prompt,expected) in [("Hello, how are you?",AppLanguage.english),("今日は会議が長くて疲れた。",.japanese),("Can you answer in English now?",.english)] {
            let language=ConversationLanguage.detect(prompt,fallback:.japanese)
            XCTAssertEqual(language,expected)
            let response=try await service.reply(to:prompt,history:history,observations:"",notes:"",replyLanguage:language.name)
            let evidence=XCTAttachment(string:"User: \(prompt)\nMate: \(response.text)")
            evidence.name="real-language-switch";evidence.lifetime = .keepAlways;add(evidence)
            XCTAssertEqual(ConversationLanguage.detect(response.text,fallback:expected == .english ? .japanese:.english),expected,response.text)
            history += [.init(isUser:true,text:prompt),.init(isUser:false,text:response.text)]
        }
    }
    private func requirePhysicalModel() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Run model-quality fixtures on the phone; simulator availability can report ready without inference assets")
        #endif
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
        let model=CompanionModel(conversation:service,planner:ChatOnlyPlanner())
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
    func testExplicitInterruptionDiscardsLateReplyAndDoesNotStartSensors() async throws {
        let service=SuspendedConversation()
        let model=CompanionModel(conversation:service,planner:ChatOnlyPlanner())
        model.readAloud=false
        model.send("hello")
        try await waitUntil{await service.waiting}
        XCTAssertTrue(model.interruptReply())
        await service.complete()
        try await Task.sleep(for:.milliseconds(50))
        XCTAssertFalse(model.thinking)
        XCTAssertFalse(model.voiceSessionActive)
        XCTAssertFalse(model.voice.listening)
        XCTAssertFalse(model.sensors.captureRequested)
        XCTAssertEqual(model.messages.count,1)
        model.rest()
    }
    func testSettingsAndBackgroundDiscardLateReplies() async throws {
        for background in [false,true] {
            let service=SuspendedConversation()
            let model=CompanionModel(conversation:service,planner:ChatOnlyPlanner())
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
        try requirePhysicalModel()
        let service=ConversationService()
        if let reason=await service.availability(){throw XCTSkip(reason)}
        var history:[ConversationTurn]=[]
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
            history += [.init(isUser:true,text:prompt),.init(isUser:false,text:response.text)]
        }
    }
}
