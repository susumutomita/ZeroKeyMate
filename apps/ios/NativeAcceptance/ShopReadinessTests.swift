import XCTest
@testable import ZeroKeyMate

@MainActor final class ShopReadinessTests: XCTestCase {
    func testTemporaryUnavailabilityRequiresAFreshSuccessfulCheck() async throws {
        var calls = 0
        let ready = try await ShopReadiness.waitForAvailability(check: {
            calls += 1
            if calls == 1 { throw URLError(.timedOut) }
            return calls == 3
        }, pause: {})
        XCTAssertTrue(ready)
        XCTAssertEqual(calls, 3)
    }
    func testPersistentUnavailabilityStopsWithoutAssumingReadiness() async throws {
        var calls = 0
        let ready = try await ShopReadiness.waitForAvailability(check: { calls += 1; return false }, pause: {})
        XCTAssertFalse(ready)
        XCTAssertEqual(calls, 3)
    }
    func testInvalidResponseNeverRetriesIntoSuccess() async {
        var calls = 0
        do {
            _ = try await ShopReadiness.waitForAvailability(check: {
                calls += 1
                if calls == 1 { throw ProductError.invalidResponse }
                return true
            }, pause: {})
            XCTFail("An untrusted response must stop the flow")
        } catch { XCTAssertEqual(calls, 1) }
    }
    func testCancellationDuringRetryStopsFurtherRequests() async {
        var calls = 0
        do {
            _ = try await ShopReadiness.waitForAvailability(check: { calls += 1; return false }, pause: { throw CancellationError() })
            XCTFail("Cancelled readiness must not resume")
        } catch { XCTAssertEqual(calls, 1) }
    }
}
