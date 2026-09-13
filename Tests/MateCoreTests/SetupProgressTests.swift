import XCTest
@testable import MateCore
final class SetupProgressTests:XCTestCase {
    func testResumeUsesActualStateAndPrioritizesPendingOperations() {
        func stage(_ restored:Bool=true,_ pending:Bool=false,_ connected:Bool=true,_ auth:Bool=true,_ wallets:Bool=true,_ checked:Bool=true,_ balance:UInt64=1,_ mandate:Bool=true)->SetupStage {
            SetupProgress(restored:restored,pending:pending,connected:connected,authenticated:auth,walletsReady:wallets,accountChecked:checked,balance:balance,mandateActive:mandate).stage
        }
        XCTAssertEqual(stage(false,true),.restoring)
        XCTAssertEqual(stage(true,true,false),.recovery)
        XCTAssertEqual(stage(true,false,false),.connection)
        XCTAssertEqual(stage(true,false,true,false),.login)
        XCTAssertEqual(stage(true,false,true,true,false),.wallets)
        XCTAssertEqual(stage(true,false,true,true,true,false),.account)
        XCTAssertEqual(stage(true,false,true,true,true,true,0),.funds)
        XCTAssertEqual(stage(true,false,true,true,true,true,1,false),.rules)
        XCTAssertEqual(stage(),.request)
        // An expired mandate or a drained execution account moves backwards;
        // neither an old checkpoint nor an earlier successful deposit can skip it.
        XCTAssertEqual(stage(true,false,true,true,true,true,0,false),.funds)
    }
}
