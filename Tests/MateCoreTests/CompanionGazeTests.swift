import XCTest
@testable import MateCore

final class CompanionGazeTests: XCTestCase {
    func testSmallDetectionJitterDoesNotKeepMovingSettledEyes() {
        var gaze = CompanionGaze()
        for frame in 0...120 {
            gaze.update(x: 0.55, y: -0.25, now: Double(frame) / 12)
        }
        let settled = gaze.position
        for frame in 121...168 {
            let jitter = frame.isMultiple(of: 2) ? 0.008 : -0.008
            let result = gaze.update(x: 0.55 + jitter, y: -0.25 - jitter, now: Double(frame) / 12)
            XCTAssertEqual(result.x, settled.x, accuracy: 0.000_001)
            XCTAssertEqual(result.y, settled.y, accuracy: 0.000_001)
        }
    }

    func testLargeTargetChangeHasBoundedSpeedAndDoesNotOvershoot() {
        var gaze = CompanionGaze()
        gaze.update(x: 1, y: -1, now: 0)
        var previous = gaze.position
        for frame in 1...36 {
            let result = gaze.update(x: 1, y: -1, now: Double(frame) / 12)
            XCTAssertLessThanOrEqual(hypot(result.x - previous.x, result.y - previous.y), 1.5 / 12 + 0.000_001)
            XCTAssertGreaterThanOrEqual(result.x, previous.x)
            XCTAssertLessThanOrEqual(result.y, previous.y)
            XCTAssertLessThanOrEqual(result.x, 1)
            XCTAssertGreaterThanOrEqual(result.y, -1)
            previous = result
        }
        XCTAssertGreaterThan(gaze.position.x, 0.99)
        let afterStall = gaze.update(x: -1, y: 1, now: 30)
        XCTAssertLessThanOrEqual(hypot(afterStall.x - previous.x, afterStall.y - previous.y), 0.15 + 0.000_001)
    }

    func testBriefFaceLossHoldsGazeThenReturnsSmoothlyToCenter() {
        var gaze = CompanionGaze()
        for frame in 0...24 {
            gaze.update(x: 0.8, y: 0.4, now: Double(frame) / 12)
        }
        let held = gaze.position
        XCTAssertEqual(gaze.update(x: nil, y: nil, now: 2.2), held)
        XCTAssertEqual(gaze.update(x: nil, y: nil, now: 2.5), held)
        let returning = gaze.update(x: nil, y: nil, now: 2.65)
        XCTAssertGreaterThan(returning.x, 0)
        XCTAssertLessThan(returning.x, held.x)
        XCTAssertGreaterThan(returning.y, 0)
        XCTAssertLessThan(returning.y, held.y)
        XCTAssertLessThanOrEqual(hypot(returning.x - held.x, returning.y - held.y), 1.5 * 0.05 + 0.000_001)
        for frame in 1...48 {
            gaze.update(x: nil, y: nil, now: 2.65 + Double(frame) / 12)
        }
        XCTAssertEqual(gaze.position.x, 0, accuracy: 0.000_01)
        XCTAssertEqual(gaze.position.y, 0, accuracy: 0.000_01)
    }

    func testInvalidCoordinatesAndTimestampsCannotPoisonGaze() {
        var gaze = CompanionGaze()
        gaze.update(x: 3, y: -4, now: 0)
        let valid = gaze.update(x: 3, y: -4, now: 0.1)
        XCTAssertEqual(gaze.update(x: -1, y: 1, now: .nan), valid)
        XCTAssertEqual(gaze.update(x: -1, y: 1, now: .infinity), valid)
        XCTAssertEqual(gaze.update(x: -1, y: 1, now: 0), valid)
        XCTAssertEqual(gaze.update(x: .nan, y: .infinity, now: 0.2), valid)
        let result = gaze.update(x: .nan, y: nil, now: 1)
        XCTAssertTrue(result.x.isFinite && result.y.isFinite)
        XCTAssertLessThan(result.x, valid.x)
        XCTAssertGreaterThan(result.y, valid.y)
    }

    func testResetImmediatelyCentersAndDiscardsOldTarget() {
        var gaze = CompanionGaze()
        gaze.update(x: 1, y: -1, now: 0)
        gaze.update(x: 1, y: -1, now: 0.1)
        XCTAssertNotEqual(gaze.position.x, 0)
        gaze.reset()
        XCTAssertEqual(gaze.position.x, 0)
        XCTAssertEqual(gaze.position.y, 0)
        XCTAssertEqual(gaze.update(x: nil, y: nil, now: 10).x, 0)
        XCTAssertEqual(gaze.update(x: nil, y: nil, now: 11).y, 0)
        let reacquired = gaze.update(x: -1, y: 1, now: 11.1)
        XCTAssertLessThan(reacquired.x, 0)
        XCTAssertGreaterThan(reacquired.y, 0)
    }
}
