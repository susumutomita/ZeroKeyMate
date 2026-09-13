import XCTest
@testable import MateCore

final class VoiceWakePhraseTests:XCTestCase {
    func testGoodnightStopsOnlyForAnExplicitShortCommand() {
        for text in ["おやすみ", "お休みなさい。", "Good night, Mate!"] {
            XCTAssertTrue(VoiceWakePhrase.isRestCommand(text))
        }
        for text in ["おやすみって英語で何？", "明日はお休みです", "I said good night", "こんにちは"] {
            XCTAssertFalse(VoiceWakePhrase.isRestCommand(text))
        }
    }
    func testGreetingAndRecognitionVariants() {
        for text in ["こんにちは", "こんにちは！", " こんにちわ。 ", "Hello, Mate!", "ハロー"] {
            XCTAssertTrue(VoiceWakePhrase.matches(text),text)
        }
    }
    func testOtherSpeechDoesNotWakeMate() {
        for text in ["", "今日は疲れた", "こんにちはと言ってみて", "Don't say hello", "明日の予定"] {
            XCTAssertFalse(VoiceWakePhrase.matches(text),text)
        }
    }
}
