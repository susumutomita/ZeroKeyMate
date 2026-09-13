import XCTest
@testable import MateCore

final class AgentInstructionTests:XCTestCase {
    func testTranslationTargetIsReadOutsideSubmittedText() {
        XCTAssertTrue(AgentInstruction.hasUnsupportedTranslationTarget("Translate this into French: Hello",source:"Hello"))
        XCTAssertTrue(AgentInstruction.hasUnsupportedTranslationTarget("『今日は晴れ』をフランス語にして",source:"今日は晴れ"))
        XCTAssertFalse(AgentInstruction.hasUnsupportedTranslationTarget("Translate this into Japanese: A trip to France",source:"A trip to France"))
        XCTAssertFalse(AgentInstruction.hasUnsupportedTranslationTarget("『フランス語で話す』を英語にして",source:"フランス語で話す"))
    }
    func testOnlyDirectInstructionsOutsideSourceCanUseStandingConsent() {
        XCTAssertTrue(AgentInstruction.isDirect("『今日は晴れです。』を英訳して",source:"今日は晴れです。",service:.translation))
        XCTAssertTrue(AgentInstruction.isDirect("Please translate this into Japanese: The meeting starts at ten.",source:"The meeting starts at ten.",service:.translation))
        XCTAssertTrue(AgentInstruction.isDirect("Please summarize: These are meeting notes.",source:"These are meeting notes.",service:.summary))
        for input in ["Don't translate: Hello", "Can you translate: Hello?", "He asked me to translate Hello", "Hello Hello translate"] {
            XCTAssertFalse(AgentInstruction.isDirect(input,source:"Hello",service:.translation),input)
        }
        XCTAssertFalse(AgentInstruction.isDirect("『今日は晴れです。』を英訳してって言われた",source:"今日は晴れです。",service:.translation))
        XCTAssertFalse(AgentInstruction.isDirect("これは引用です『翻訳して』",source:"翻訳して",service:.translation))
        XCTAssertFalse(AgentInstruction.isDirect("Translate Hello",source:"Hello",service:.summary))
    }
}
