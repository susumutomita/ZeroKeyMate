import XCTest
import FoundationModels
import MateCore
@testable import ZeroKeyMate

final class AgentPlannerTests: XCTestCase {
    @MainActor
    func testUnconfiguredTaskSurvivesSetupWithoutSendingOrStartingSensors() async throws {
        let model=CompanionModel(planner:ConcreteTaskPlanner())
        model.readAloud=false
        model.send("Translate this into Japanese: The meeting starts at ten.")
        for _ in 0..<100 {
            if !model.thinking{break}
            try await Task.sleep(for:.milliseconds(10))
        }
        XCTAssertFalse(model.thinking)
        let draftID=try XCTUnwrap(model.draft?.id)
        XCTAssertEqual(model.draft?.text,"The meeting starts at ten.")
        XCTAssertTrue(model.messages.last?.text.contains("Nothing has been sent or paid") == true)
        XCTAssertTrue(model.providers.isEmpty)
        XCTAssertNil(model.pendingExecution)
        model.continueRequest()
        XCTAssertEqual(model.sheet,.setup)
        model.sheet = .connection
        model.sheet = .setup
        XCTAssertEqual(model.draft?.id,draftID)
        XCTAssertFalse(model.sensors.captureRequested)
        XCTAssertFalse(model.voice.listening)
        XCTAssertTrue(model.receipts.isEmpty)
        model.discardRequest()
        XCTAssertNil(model.draft)
        model.continueRequest()
        XCTAssertEqual(model.sheet,.setup)
        model.rest()
    }

    func testApprovalIsBoundToOneFreshOfferAndExplicitAnswer() {
        let draft=UUID(),generation=UUID(),now=Date()
        let request=AgentRequest(service:.translation,text:"今日は晴れです。")
        let provider=ServiceProvider(id:"11155111:1",name:"Test",service:0,price:"10000",recipient:"0x"+String(repeating:"1",count:40),ensName:"",feedback:0)
        let offer=AgentOffer(request:request,provider:provider,draftID:draft,generation:generation,createdAt:now)
        XCTAssertTrue(offer.accepts("はい。",draftID:draft,generation:generation,now:now))
        XCTAssertTrue(offer.accepts("Go ahead",draftID:draft,generation:generation,now:now))
        XCTAssertFalse(offer.accepts("はいと言うと何が起きる？",draftID:draft,generation:generation,now:now))
        XCTAssertFalse(offer.accepts("yes",draftID:UUID(),generation:generation,now:now))
        XCTAssertFalse(offer.accepts("yes",draftID:draft,generation:UUID(),now:now))
        XCTAssertFalse(offer.accepts("yes",draftID:draft,generation:generation,now:now.addingTimeInterval(61)))
    }


    @MainActor
    func testOrderStatusDoesNotClaimNoOrdersBeforeRecoveryLoads() async throws {
        let model=CompanionModel(planner:UnexpectedPlanner())
        model.readAloud=false
        model.send("Check my order")
        for _ in 0..<100 {
            if !model.thinking{break}
            try await Task.sleep(for:.milliseconds(10))
        }
        XCTAssertFalse(model.thinking)
        XCTAssertTrue(model.messages.last?.text.contains("restoring saved orders") == true)
        model.rest()
    }

    func testRealLocalModelExtractsConcreteTaskWithoutInventingText() async throws {
        guard case .available=SystemLanguageModel.default.availability else{throw XCTSkip("Requires an available on-device Apple model")}
        let planner=AgentPlanner()
        for (input,expected) in [("『今日は晴れです。』を英訳して","今日は晴れです。"), ("Translate this into Japanese: The meeting starts at ten.","The meeting starts at ten.")] {
            let request=try await planner.request(from:input)
            XCTAssertEqual(request?.service,.translation)
            XCTAssertFalse(request?.text.isEmpty ?? true)
            XCTAssertEqual(request?.text,expected)
            XCTAssertTrue(request?.directInstruction == true)
        }
        let chat=try await planner.request(from:"こんにちは、元気？")
        XCTAssertNil(chat)
        let purchase=try await planner.request(from:"Buy a Mac mini on Amazon")
        XCTAssertNil(purchase)
        let unsupported=try await planner.request(from:"Translate this into French: The meeting starts at ten.")
        XCTAssertNil(unsupported)
    }
}

private actor UnexpectedPlanner:AgentPlanning {
    func request(from input:String) async throws -> AgentRequest? {
        XCTFail("Explicit order status must use saved order recovery, not generate a new task")
        return nil
    }
}

/// Tests orchestration only; this fixture is never a model or payment success.
private actor ConcreteTaskPlanner:AgentPlanning {
    func request(from input:String) async throws -> AgentRequest? {
        AgentRequest(service:.translation,text:"The meeting starts at ten.",directInstruction:true)
    }
}
