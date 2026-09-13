import XCTest
@testable import MateCore

final class VoiceTurnTests: XCTestCase {
    func testSilenceEndsAndDoesNotSubmitEmptyInput() {
        var turn = VoiceTurn(now: 100)
        XCTAssertEqual(turn.poll(now: 114), .waiting)
        XCTAssertEqual(turn.poll(now: 115), .silence)
        XCTAssertEqual(turn.update("late callback", now: 116, final: true), .waiting)
    }
    func testUnchangedPartialResultsCannotExtendTheSilenceDeadline() {
        var turn = VoiceTurn(now: 0)
        XCTAssertEqual(turn.update("Hello", now: 1), .waiting)
        XCTAssertEqual(turn.update("Hello", now: 2), .waiting)
        XCTAssertEqual(turn.poll(now: 3), .submit("Hello"))
        XCTAssertEqual(turn.update("Hello", now: 3.1, final: true), .waiting)
    }
    func testGrowingSpeechIsBoundedAndNewTurnIsIndependent() {
        var turn = VoiceTurn(now: 0)
        for second in 1..<60 {
            XCTAssertEqual(turn.update("words \(second)", now: Double(second)), .waiting)
        }
        XCTAssertEqual(turn.update("last words", now: 60), .submit("last words"))
        var next = VoiceTurn(now: 61)
        XCTAssertEqual(next.update(" next ", now: 62, final: true), .submit("next"))
        XCTAssertEqual(next.poll(now: 80), .waiting)
    }
}
