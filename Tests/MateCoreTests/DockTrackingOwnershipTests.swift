import XCTest
@testable import MateCore

final class DockTrackingOwnershipTests:XCTestCase {
    func testLaunchDoesNotDisableSystemTracking() {
        var ownership=DockTrackingOwnership()
        XCTAssertFalse(ownership.shouldApply(enabled:false))
        XCTAssertFalse(ownership.shouldApply(enabled:false))
    }
    func testStopIsAppliedAfterOurStartIncludingAnUncertainStart() {
        var ownership=DockTrackingOwnership()
        XCTAssertTrue(ownership.shouldApply(enabled:true))
        XCTAssertTrue(ownership.shouldApply(enabled:false))
    }
}
