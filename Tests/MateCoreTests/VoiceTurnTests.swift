import XCTest
@testable import MateCore

final class VoiceTurnTests: XCTestCase {
    func testAudioActivityProtectsAnUnchangedTranscriptAndQuietCanSubmitSooner() {
        var turn=VoiceTurn(now:0,usesAudioActivity:true)
        XCTAssertEqual(turn.update("I'd like",now:1),.waiting)
        turn.noteAudioActivity(now:2)
        XCTAssertEqual(turn.poll(now:2.5),.waiting)
        XCTAssertEqual(turn.update("I'd like water",now:2.5),.waiting)
        XCTAssertEqual(turn.poll(now:2.89),.waiting)
        XCTAssertEqual(turn.poll(now:2.91),.submit("I'd like water"))
        turn.noteAudioActivity(now:3)
        XCTAssertEqual(turn.update("late",now:3.1,final:true),.waiting)
    }
    func testAudioActivityDoesNotRemoveMaximumTurnOrQuietInputBounds() {
        var noisy=VoiceTurn(now:0,usesAudioActivity:true)
        for second in 1..<60 {
            noisy.noteAudioActivity(now:Double(second))
            XCTAssertEqual(noisy.update("Hello",now:Double(second)),.waiting)
        }
        noisy.noteAudioActivity(now:60)
        XCTAssertEqual(noisy.poll(now:60),.submit("Hello"))
        var quiet=VoiceTurn(now:0,usesAudioActivity:true)
        XCTAssertEqual(quiet.poll(now:15),.silence)
    }
    func testReplyCanStartAfterShortPauseButContinuingSpeechResetsDeadline() {
        var turn=VoiceTurn(now:0)
        XCTAssertEqual(turn.update("Hello",now:1),.waiting)
        XCTAssertEqual(turn.poll(now:2.1),.waiting)
        XCTAssertEqual(turn.update("Hello Mate",now:2.1),.waiting)
        XCTAssertEqual(turn.poll(now:3.2),.waiting)
        XCTAssertEqual(turn.poll(now:3.4),.submit("Hello Mate"))
        XCTAssertEqual(turn.update("late final",now:4,final:true),.waiting)
    }
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
