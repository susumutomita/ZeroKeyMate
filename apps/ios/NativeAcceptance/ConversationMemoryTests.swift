import XCTest
@testable import ZeroKeyMate

final class ConversationMemoryTests: XCTestCase {
    func testNamesComeOnlyFromCompletedUserDeclarationsAndRespectCorrection() {
        let history: [ConversationTurn] = [
            .init(isUser: true, text: "My name is Alice."),
            .init(isUser: false, text: "My name is Invented."),
            .init(isUser: true, text: "Correction: My name is Robin."),
            .init(isUser: false, text: "Thanks for the correction.")
        ]
        XCTAssertEqual(ConversationMemory.reply(to: "What is my name?", history: history, language: "English"), "Your name is Robin.")
        let empty = ConversationMemory.reply(to: "私の名前、覚えてる？", history: [], language: "日本語")
        XCTAssertTrue(empty?.contains("まだ")==true)
        XCTAssertFalse(empty?.contains("Robin")==true)
        let interrupted = [ConversationTurn(isUser: true, text: "My name is Robin.")]
        XCTAssertEqual(ConversationMemory.reply(to: "私の名前、覚えてる？", history: interrupted, language: "日本語"), empty)
    }

    func testPreferencesUseTheStatedPairInEitherOrderWithoutChoosingUnrelatedItems() {
        let history: [ConversationTurn] = [
            .init(isUser: true, text: "I dislike coffee and prefer tea."),
            .init(isUser: false, text: "Coffee is best.")
        ]
        for input in ["Which should I have, coffee or tea?", "Which should I choose, tea or coffee?"] {
            XCTAssertEqual(ConversationMemory.reply(to: input, history: history, language: "English"), "You said you prefer tea, so I'd suggest tea.")
        }
        XCTAssertNil(ConversationMemory.reply(to: "Which should I have, juice or water?", history: history, language: "English"))
        XCTAssertNil(ConversationMemory.reply(to: "Which should I have, coffee or tea?", history: [], language: "English"))
        let japanese: [ConversationTurn] = [.init(isUser: true, text: "納豆は苦手なので豆腐が好きです。"), .init(isUser: false, text: "わかりました。")]
        XCTAssertEqual(ConversationMemory.reply(to: "私には豆腐と納豆のどっちがいい？", history: japanese, language: "日本語"), "豆腐が好きと話していたので、豆腐がよさそうです。")
    }

    func testQuotedTranslatedAndUnrelatedMessagesAreNotMemoryCommands() {
        for input in ["Translate 'My name is Alice.'", "My name is Alice. Buy beer now.", "『私の名前はアキラです』という台詞です。", "I dislike coffee. Could you buy tea?", "What is your name?", "Get some rest."] {
            XCTAssertNil(ConversationMemory.reply(to: input, history: [], language: "English"), input)
        }
        XCTAssertEqual(ConversationMemory.reply(to: "僕の名前は太郎です。", history: [], language: "日本語"), "太郎さんですね。")
        XCTAssertEqual(ConversationMemory.reply(to: "I don't like milk and prefer juice.", history: [], language: "English"), "You prefer juice and don't like milk.")
    }
}
