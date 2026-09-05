import Foundation
import Security
import XCTest
import Verity
@testable import ZeroKeyMate

final class RuntimeDiagnosticsTests: XCTestCase {
    func testKeychainPersistsAndDeletesPrivateState() throws {
        let key = "acceptance-" + UUID().uuidString
        defer { try? LocalSecrets.delete(key) }
        XCTAssertNil(try LocalSecrets.read(String.self, key: key))
        try LocalSecrets.write("private acceptance value", key: key)
        XCTAssertEqual(try LocalSecrets.read(String.self, key: key), "private acceptance value")
        try LocalSecrets.delete(key)
        XCTAssertNil(try LocalSecrets.read(String.self, key: key))
    }

    func testBundledSchemeFileAndMemoryLoadingAreCompatible() throws {
        let runtime = try Verity(backend: .provekit)
        for ext in ["pkp", "pkv"] {
            let url = try XCTUnwrap(Bundle.main.url(forResource: "mate_policy", withExtension: ext))
            for memory in [false, true] {
                do {
                    if ext == "pkp" {
                        let scheme = try memory ? runtime.loadProver(data: Data(contentsOf: url)) : runtime.loadProver(from: url)
                        scheme.close()
                    } else {
                        let scheme = try memory ? runtime.loadVerifier(data: Data(contentsOf: url)) : runtime.loadVerifier(from: url)
                        scheme.close()
                    }
                } catch {
                    let diagnostic = (try? Verity.lastErrorMessage(for: .provekit)) ?? "No upstream diagnostic"
                    XCTFail("Scheme \(ext), memory=\(memory): \(error); \(diagnostic)")
                }
            }
        }
    }
}
