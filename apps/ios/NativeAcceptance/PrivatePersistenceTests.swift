import Foundation
import XCTest
@testable import ZeroKeyMate

final class PrivatePersistenceTests: XCTestCase {
    func testLargeRetryEnvelopeUsesSealedStorage() throws {
        let name="test-envelope-"+UUID().uuidString
        defer { try? PrivateFiles.delete(name) }
        let payload=Data(repeating:0x5a,count:128_000)
        try PrivateFiles.write(payload,name:name)
        XCTAssertEqual(try PrivateFiles.read(Data.self,name:name),payload)
        try PrivateFiles.delete(name)
        XCTAssertNil(try PrivateFiles.read(Data.self,name:name))
    }
}
