import XCTest
@testable import MateCore

final class SpokenTextBufferTests:XCTestCase {
    func testJapaneseStartsBeforeTheRestOfTheReplyAndDoesNotRepeatSnapshots() {
        var buffer=SpokenTextBuffer()
        XCTAssertEqual(buffer.consume("こんにちは"),[])
        XCTAssertEqual(buffer.consume("こんにちは。今日は"),["こんにちは。"])
        XCTAssertEqual(buffer.consume("こんにちは。今日は"),[])
        XCTAssertEqual(buffer.consume("こんにちは。今日はどうでしたか？"),["今日はどうでしたか？"])
        XCTAssertEqual(buffer.consume("こんにちは。今日はどうでしたか？",final:true),[])
    }
    func testEnglishKeepsWordsAndDecimalAmountsTogether() {
        var buffer=SpokenTextBuffer()
        XCTAssertEqual(buffer.consume("The price is 0."),[])
        XCTAssertEqual(buffer.consume("The price is 0.10 USDC. You"),["The price is 0.10 USDC."])
        XCTAssertEqual(buffer.consume("The price is 0.10 USDC. You can check it",final:true),["You can check it"])
        XCTAssertEqual(buffer.consume("The price is 0.10 USDC. You can check it",final:true),[])
    }
    func testRevisedUnspokenTextIsAllowedButSpokenPrefixesAreNeverReplayed() {
        var buffer=SpokenTextBuffer()
        XCTAssertEqual(buffer.consume("The thing is"),[])
        XCTAssertEqual(buffer.consume("Hello!"),["Hello!"])
        XCTAssertEqual(buffer.consume("Goodbye!",final:true),[])
        XCTAssertEqual(buffer.consume("Hello! Welcome.",final:true),["Welcome."])
    }
    func testIndependentResponsesAndWhitespaceOnlyFinal() {
        var first=SpokenTextBuffer()
        XCTAssertEqual(first.consume("A short answer",final:true),["A short answer"])
        var next=SpokenTextBuffer()
        XCTAssertEqual(next.consume("A short answer",final:true),["A short answer"])
        var empty=SpokenTextBuffer()
        XCTAssertEqual(empty.consume(" \n ",final:true),[])
    }
}
