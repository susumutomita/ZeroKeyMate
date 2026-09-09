import XCTest
@testable import MateCore

final class ConversationIntentTests: XCTestCase {
    func testUsageStatusPhrasesMatchInBothLanguages() {
        for text in ["今いくら使った？", "利用状況を教えて", "残高はいくら？", "How much have I spent today?", "What's my balance?"] {
            XCTAssertTrue(ConversationRouter.isUsageStatusRequest(text), text)
        }
        for text in ["こんにちは", "Translate this for me", "5 USDCまで翻訳に使っていい"] {
            XCTAssertFalse(ConversationRouter.isUsageStatusRequest(text), text)
        }
    }
    func testRevokePhrasesMatchInBothLanguages() {
        for text in ["委任を取り消して", "権限を取り消してください", "Revoke the mandate", "Please revoke my mandate"] {
            XCTAssertTrue(ConversationRouter.isRevokeRequest(text), text)
        }
        for text in ["こんにちは", "5 USDCまで使っていい", "How much have I spent?"] {
            XCTAssertFalse(ConversationRouter.isRevokeRequest(text), text)
        }
    }
    func testRuleProposalRequiresAnExplicitUSDCAmount() {
        XCTAssertNil(ConversationRouter.ruleProposal(from: "5番目の会議室でお願いします"))
        XCTAssertNil(ConversationRouter.ruleProposal(from: "翻訳をお願いします"))
        guard let proposal = ConversationRouter.ruleProposal(from: "今日は5 USDCまで、翻訳に使っていい") else {
            return XCTFail("expected a rule proposal")
        }
        XCTAssertEqual(proposal.budgetUnits, 5_000_000)
        XCTAssertTrue(proposal.translation)
        XCTAssertFalse(proposal.summary)
        XCTAssertNil(proposal.unsupportedService)
        XCTAssertNotNil(proposal.hours)
    }
    func testRuleProposalFlagsAnUnsupportedService() {
        guard let proposal = ConversationRouter.ruleProposal(from: "10.5 USDCまで、翻訳と調査に使っていい") else {
            return XCTFail("expected a rule proposal")
        }
        XCTAssertEqual(proposal.budgetUnits, 10_500_000)
        XCTAssertTrue(proposal.translation)
        XCTAssertEqual(proposal.unsupportedService, "調査")
    }
    func testTodayBecomesHoursUntilLocalMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        let timeZone = TimeZone(identifier: "Asia/Tokyo")!
        calendar.timeZone = timeZone
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 20, minute: 0))!
        let proposal = ConversationRouter.ruleProposal(from: "today up to 3 USDC for summary", now: now, timeZone: timeZone)
        XCTAssertEqual(proposal?.hours, 4)
    }
    func testNoPeriodPhraseLeavesHoursUnset() {
        let proposal = ConversationRouter.ruleProposal(from: "3 USDCまで要約に使っていい")
        XCTAssertNil(proposal?.hours)
    }
}
