import XCTest
@testable import ZeroKeyMate

@MainActor
final class ProofInspectionTests: XCTestCase {
    func testInspectionProducesFreshVerifiedProofsWithoutAnAccount() async throws {
        let model=ProofInspectionModel()
        await model.run()
        XCTAssertNil(model.error)
        let first=try XCTUnwrap(model.result)
        XCTAssertTrue(model.tamperingRejected)
        XCTAssertGreaterThan(first.bytes.count,100)
        await model.run()
        XCTAssertNil(model.error)
        let second=try XCTUnwrap(model.result)
        XCTAssertNotEqual(first.policyHash,second.policyHash)
        XCTAssertNotEqual(first.actionHash,second.actionHash)
    }
    func testLocalPrecheckIsNotReportedAsSuccessfulProof() async {
        let model=ProofInspectionModel()
        model.amount="6"
        await model.run()
        XCTAssertNil(model.result)
        XCTAssertNotNil(model.error)
        model.amount="3";model.allowsSummary=false
        await model.run()
        XCTAssertNil(model.result)
        XCTAssertNotNil(model.error)
    }
}
