import XCTest
@testable import MateCore

final class SpeechTranscriptTests: XCTestCase {
    func testCorrectionsReplaceVolatileWordsAndFinalSegmentsAccumulate() {
        var transcript = SpeechTranscript()
        transcript.update("Buy bear", start: 0, end: 1, isFinal: false)
        transcript.update("Buy beer", start: 0, end: 1.2, isFinal: false)
        XCTAssertEqual(transcript.text, "Buy beer")
        transcript.update("Buy beer", start: 0, end: 1.2, isFinal: true)
        transcript.update(" please", start: 1.2, end: 2, isFinal: false)
        XCTAssertEqual(transcript.text, "Buy beer please")
        transcript.update(" please.", start: 1.2, end: 2, isFinal: true)
        XCTAssertEqual(transcript.text, "Buy beer please.")
        transcript.update("Buy bear", start: 0, end: 1, isFinal: true)
        XCTAssertEqual(transcript.text, "Buy beer please.")
    }
    func testJapaneseAndInvalidOrOverlappingRanges() {
        var transcript = SpeechTranscript()
        transcript.update("ビールを", start: 0, end: 1, isFinal: true)
        transcript.update("炭酸水", start: 0.5, end: 2, isFinal: false)
        transcript.update("ignored", start: .nan, end: 2, isFinal: false)
        transcript.update("ignored", start: 1, end: 1, isFinal: false)
        transcript.update("2本ください。", start: 1, end: 2, isFinal: true)
        XCTAssertEqual(transcript.text, "ビールを2本ください。")
        XCTAssertEqual(SpeechTranscript().text, "")
    }
}
