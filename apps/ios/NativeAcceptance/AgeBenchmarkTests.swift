import XCTest
@testable import ZeroKeyMate

final class AgeBenchmarkTests: XCTestCase {
    func testSyntheticBackendsVerifyAndRejectChangedOrder() async throws {
        let service = AgeBenchmarkService()
        guard await service.available(.groth16), await service.available(.whir) else {
            throw XCTSkip("Matching native runtime and public benchmark setup are not staged")
        }
        var reports: [AgeBenchmarkService.Report] = []
        defer {
            if let data = try? JSONEncoder().encode(reports) {
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                attachment.name = "synthetic-age-backend-timings"; attachment.lifetime = .keepAlways; add(attachment)
            }
        }
        for backend in [AgeBenchmarkService.Backend.groth16, .whir, .groth16, .whir] {
            let report = try await service.run(backend)
            reports.append(report)
            XCTAssertTrue(report.syntheticOnly)
            XCTAssertTrue(report.native.changedOrderRejected)
            XCTAssertEqual(report.native.timing.workerThreads, 2)
            XCTAssertGreaterThan(report.native.timing.witnessAndProofMicroseconds, 0)
            XCTAssertGreaterThan(report.native.serializedProofBytes, 0)
        }
    }
}
