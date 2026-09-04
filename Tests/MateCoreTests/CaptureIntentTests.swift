import XCTest
@testable import MateCore

final class CaptureIntentTests: XCTestCase {
    func testStartsWithCaptureDisabled() {
        let intent = CaptureIntent()
        XCTAssertFalse(intent.shouldCapture)
        XCTAssertFalse(intent.isRequested)
    }

    func testEnteringForegroundDoesNotStartCapture() {
        var intent = CaptureIntent()
        intent.setForeground(true)
        XCTAssertFalse(intent.shouldCapture)
    }

    func testExplicitStartInForegroundEnablesIntent() {
        var intent = CaptureIntent()
        intent.setForeground(true)
        intent.requestStart()
        XCTAssertTrue(intent.shouldCapture)
    }

    func testStartInBackgroundIsIgnored() {
        var intent = CaptureIntent()
        intent.requestStart()
        intent.setForeground(true)
        XCTAssertFalse(intent.shouldCapture)
    }

    func testStopClearsIntentImmediately() {
        var intent = CaptureIntent()
        intent.setForeground(true)
        intent.requestStart()
        intent.requestStop()
        XCTAssertFalse(intent.shouldCapture)
    }

    func testBackgroundClearsPendingStart() {
        var intent = CaptureIntent()
        intent.setForeground(true)
        intent.requestStart()
        intent.setForeground(false)
        XCTAssertFalse(intent.isRequested)
        XCTAssertFalse(intent.shouldCapture)
    }

    func testForegroundReturnDoesNotResumeCapture() {
        var intent = CaptureIntent()
        intent.setForeground(true)
        intent.requestStart()
        intent.setForeground(false)
        intent.setForeground(true)
        XCTAssertFalse(intent.shouldCapture)
    }

    func testUserCanExplicitlyRestartAfterBackground() {
        var intent = CaptureIntent()
        intent.setForeground(true)
        intent.requestStart()
        intent.setForeground(false)
        intent.setForeground(true)
        intent.requestStart()
        XCTAssertTrue(intent.shouldCapture)
    }

    func testRepeatedForegroundEventDoesNotCancelExplicitStart() {
        var intent = CaptureIntent()
        intent.setForeground(true)
        intent.requestStart()
        intent.setForeground(true)
        XCTAssertTrue(intent.shouldCapture)
    }

    func testStopIsIdempotent() {
        var intent = CaptureIntent()
        intent.requestStop()
        intent.requestStop()
        XCTAssertEqual(intent, CaptureIntent())
    }

    func testAllEventSequencesRequireExplicitForegroundConsent() {
        // Exhaustively exercise every sequence of six lifecycle/user events.
        for sequence in 0..<4096 {
            var intent = CaptureIntent()
            var foreground = false
            var consent = false
            var remaining = sequence
            for _ in 0..<6 {
                switch remaining % 4 {
                case 0:
                    foreground = true
                    intent.setForeground(true)
                case 1:
                    foreground = false
                    consent = false
                    intent.setForeground(false)
                case 2:
                    consent = foreground
                    intent.requestStart()
                default:
                    consent = false
                    intent.requestStop()
                }
                remaining /= 4
                XCTAssertEqual(intent.shouldCapture, foreground && consent)
                if !foreground { XCTAssertFalse(intent.isRequested) }
            }
        }
    }
}
