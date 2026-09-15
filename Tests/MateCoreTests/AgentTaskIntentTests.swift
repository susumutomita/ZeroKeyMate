import XCTest
@testable import MateCore

final class AgentTaskIntentTests:XCTestCase {
    func testEverydayConversationSkipsTaskModel() {
        for input in ["こんにちは","今日は会議が長くて疲れた","さっきのマグカップは何色？","Hello, how are you?","What do you think?","Tell me a joke"] {
            XCTAssertFalse(AgentTaskIntent.needsPlanning(input),input)
        }
    }
    func testTaskCandidatesStillReachStructuredPlanner() {
        for input in ["Translate this to Japanese: good morning","Summarise this: The meeting is over.","Sum up this report","Say this in English: おはよう","Give me the gist of this report","Please shorten this text","これを英訳して：おはよう","以下を日本語にしてください","この文章をまとめて","要約できる？","『翻訳して』とは何ですか？"] {
            XCTAssertTrue(AgentTaskIntent.needsPlanning(input),input)
        }
    }
}
