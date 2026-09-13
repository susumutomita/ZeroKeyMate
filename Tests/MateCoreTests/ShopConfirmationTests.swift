import XCTest
@testable import MateCore

final class ShopConfirmationTests: XCTestCase {
    @MainActor func testTransientReadFailureCanRecoverWithoutAnotherPayment() async throws {
        var reads = 0
        var delays: [UInt64] = []
        let finished = try await ShopConfirmation.observe(check: {
            reads += 1
            if reads == 1 { throw URLError(.timedOut) }
            return reads == 3
        }, wait: { delays.append($0) })
        XCTAssertTrue(finished)
        XCTAssertEqual(reads, 3)
        XCTAssertEqual(delays, [1, 2, 4])
    }
    @MainActor func testUnconfirmedPaymentStopsAfterBoundedObservation() async throws {
        var reads = 0
        var elapsed: UInt64 = 0
        let finished = try await ShopConfirmation.observe(check: {
            reads += 1
            throw URLError(.notConnectedToInternet)
        }, wait: { elapsed += $0 })
        XCTAssertFalse(finished)
        XCTAssertEqual(reads, 6)
        XCTAssertEqual(elapsed, 50)
    }
    @MainActor func testClosingWhileWaitingPreventsAnyFurtherRead() async {
        var reads = 0
        do {
            _ = try await ShopConfirmation.observe(check: { reads += 1; return false },
                wait: { _ in throw CancellationError() })
            XCTFail("A cancelled wait must stop observation")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(reads, 0)
    }
    @MainActor func testCancelledReadIsNotRetried() async {
        var reads = 0
        do {
            _ = try await ShopConfirmation.observe(check: {
                reads += 1; throw CancellationError()
            }, wait: { _ in })
            XCTFail("A cancelled request must stop observation")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(reads, 1)
    }
}
