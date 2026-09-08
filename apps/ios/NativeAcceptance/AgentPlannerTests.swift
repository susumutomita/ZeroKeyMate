import XCTest
import FoundationModels
import MateCore
@testable import ZeroKeyMate

final class AgentPlannerTests: XCTestCase {
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

    func testRealLocalModelExtractsConcreteTaskWithoutInventingText() async throws {
        guard case .available=SystemLanguageModel.default.availability else{throw XCTSkip("Requires an available on-device Apple model")}
        let planner=AgentPlanner()
        for input in ["『今日は晴れです。』を英訳して", "Translate this into Japanese: The meeting starts at ten."] {
            let request=try await planner.request(from:input)
            XCTAssertEqual(request?.service,.translation)
            XCTAssertFalse(request?.text.isEmpty ?? true)
            XCTAssertTrue(input.contains(request?.text ?? "not present"))
        }
        let chat=try await planner.request(from:"こんにちは、元気？")
        XCTAssertNil(chat)
        let purchase=try await planner.request(from:"Buy a Mac mini on Amazon")
        XCTAssertNil(purchase)
    }
}
