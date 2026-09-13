import XCTest
@testable import MateCore

final class CompanionActivityTests:XCTestCase {
    func testStoppedAndUnconfirmedWorkCannotLookSuccessful() {
        func state(rest:Bool=false,operation:CompanionActivity?=nil,pending:Bool=false,outcome:CompanionOutcome?=nil)->CompanionActivity {
            .resolve(resting:rest,operation:operation,pending:pending,outcome:outcome,
                     approval:false,speaking:false,listening:false,thinking:false)
        }
        XCTAssertEqual(state(rest:true,operation:.confirming,pending:true,outcome:.confirmed),.resting)
        XCTAssertEqual(state(pending:true,outcome:.confirmed),.unknown)
        XCTAssertEqual(state(operation:.sending,pending:true,outcome:.confirmed),.sending)
        XCTAssertEqual(state(operation:.confirming,pending:true),.confirming)
        XCTAssertEqual(state(outcome:.confirmed),.confirmed)
        XCTAssertEqual(state(outcome:.rejected),.rejected)
        XCTAssertFalse(CompanionActivity.unknown.processing)
    }
    func testApprovalAndVoiceHaveDistinctAccessibleStates() {
        XCTAssertEqual(CompanionActivity.resolve(resting:false,operation:nil,pending:false,outcome:nil,
            approval:true,speaking:true,listening:false,thinking:false),.approval)
        XCTAssertEqual(CompanionActivity.resolve(resting:false,operation:nil,pending:false,outcome:nil,
            approval:false,speaking:true,listening:false,thinking:false),.speaking)
        XCTAssertEqual(CompanionActivity.resolve(resting:false,operation:nil,pending:false,outcome:nil,
            approval:false,speaking:false,listening:true,thinking:false),.listening)
    }
}
