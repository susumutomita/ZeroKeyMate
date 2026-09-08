import XCTest
@testable import ZeroKeyMate

final class ConversationLanguageTests:XCTestCase {
    func testEachMessageSelectsItsOwnReplyLanguage() {
        XCTAssertEqual(ConversationLanguage.detect("こんにちは",fallback:.english),.japanese)
        XCTAssertEqual(ConversationLanguage.detect("今日は疲れた",fallback:.english),.japanese)
        XCTAssertEqual(ConversationLanguage.detect("Mac miniをAmazonで買って",fallback:.english),.japanese)
        XCTAssertEqual(ConversationLanguage.detect("Hello, how are you?",fallback:.japanese),.english)
        XCTAssertEqual(ConversationLanguage.detect("I had a long meeting today.",fallback:.japanese),.english)
        XCTAssertEqual(ConversationLanguage.detect("123",fallback:.japanese),.japanese)
    }
}
