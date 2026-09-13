import XCTest
@testable import MateCore
final class DockReactionPlanTests:XCTestCase {
    func testFiniteReactionRespectsPositionSpeedAndCallRate() throws {
        for center in [-0.99,0,0.99] {
            let plan=try XCTUnwrap(DockReactionPlan(center:center,range:-1..<1,maximumSpeed:1))
            XCTAssertEqual(plan.positions.count,3)
            XCTAssertEqual(plan.positions.last,center)
            XCTAssertLessThanOrEqual(plan.maximumSpeed,0.1)
            XCTAssertGreaterThanOrEqual(plan.stepSeconds,0.5)
            for value in plan.positions {
                XCTAssertTrue(plan.permittedRange.contains(value))
                XCTAssertLessThanOrEqual(abs(value-center),0.030001)
            }
            var previous=center
            for value in plan.positions {
                XCTAssertLessThanOrEqual(abs(value-previous)/plan.stepSeconds,plan.maximumSpeed+0.000001)
                previous=value
            }
        }
    }
    func testNoReactionWithoutSafeRoomOrUsableSpeed() {
        for center in [Double.nan,Double.infinity,-1,1] {
            XCTAssertNil(DockReactionPlan(center:center,range:-1..<1,maximumSpeed:1))
        }
        XCTAssertNil(DockReactionPlan(center:0,range:-1..<1,maximumSpeed:0.001))
        XCTAssertNil(DockReactionPlan(center:0,range:-1..<1,maximumSpeed:.infinity))
    }
    func testStopAndReenableCannotResumeAnOldMotionOrQueueOverlappingResults() throws {
        var gate=DockReactionGate()
        XCTAssertFalse(gate.request(.confirmed,allowed:false,now:0))
        XCTAssertTrue(gate.request(.confirmed,allowed:true,now:0))
        XCTAssertFalse(gate.request(.rejected,allowed:true,now:5))
        let first=try XCTUnwrap(gate.begin(allowed:true))
        XCTAssertTrue(gate.permits(first.ticket,allowed:true))
        gate.update(allowed:false);gate.update(allowed:true)
        XCTAssertFalse(gate.permits(first.ticket,allowed:true))
        XCTAssertFalse(gate.request(.confirmed,allowed:true,now:5))
        gate.finish(first.ticket)
        XCTAssertTrue(gate.request(.rejected,allowed:true,now:5))
        gate.update(allowed:false)
        XCTAssertNil(gate.begin(allowed:true))
        XCTAssertFalse(gate.request(.confirmed,allowed:true,now:6))
        XCTAssertTrue(gate.request(.confirmed,allowed:true,now:9))
    }
}
