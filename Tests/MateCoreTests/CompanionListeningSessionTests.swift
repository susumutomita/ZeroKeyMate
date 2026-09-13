import XCTest
@testable import MateCore

final class CompanionListeningSessionTests:XCTestCase {
    func testThirtySecondsOfSilenceCanRenewWithoutSubmittingOrEndingUserIntent() {
        var session=CompanionListeningSession()
        session.begin()
        let ticket=session.revision
        for start in [0.0,15.0] {
            var recognition=VoiceTurn(now:start)
            XCTAssertEqual(recognition.poll(now:start+15),.silence)
            XCTAssertTrue(session.permitsResume(ticket:ticket,foreground:true,resting:false,busy:false,screenAllowsListening:true))
        }
        var next=VoiceTurn(now:30)
        XCTAssertEqual(next.update("また話そう",now:31,final:true),.submit("また話そう"))
    }
    func testStoppedAndReopenedSessionCannotAcceptAnOldResumeCallback() {
        var session=CompanionListeningSession();session.begin()
        let old=session.revision
        session.stop()
        XCTAssertFalse(session.permitsResume(ticket:old,foreground:true,resting:false,busy:false,screenAllowsListening:true))
        session.begin()
        XCTAssertFalse(session.permitsResume(ticket:old,foreground:true,resting:false,busy:false,screenAllowsListening:true))
        XCTAssertTrue(session.permitsResume(ticket:session.revision,foreground:true,resting:false,busy:false,screenAllowsListening:true))
    }
    func testBackgroundRestBusyAndPrivateScreensBlockRenewal() {
        var session=CompanionListeningSession();session.begin()
        for conditions in [(false,false,false,true),(true,true,false,true),(true,false,true,true),(true,false,false,false)] {
            XCTAssertFalse(session.permitsResume(ticket:session.revision,foreground:conditions.0,resting:conditions.1,busy:conditions.2,screenAllowsListening:conditions.3))
        }
    }
}
