import Foundation
import XCTest
@testable import MateCore

final class EthereumEncodingTests: XCTestCase {
    func testPublicKeccakAndENSVectors() throws {
        XCTAssertEqual(CanonicalBytes.hexString(EthereumKeccak.digest(Data())),
            "0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470")
        XCTAssertEqual(CanonicalBytes.hexString(EthereumKeccak.digest(Data("abc".utf8))),
            "0x4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45")
        XCTAssertEqual(CanonicalBytes.hexString(try EthereumABI.namehash("eth")),
            "0x93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae")
        XCTAssertEqual(try EthereumABI.call("transfer(address,uint256)", []).prefix(10), "0xa9059cbb")
    }
    func testABIDynamicOffsetsAndNameValidation() throws {
        let data = try EthereumABI.call("setText(bytes32,string,string)", [
            .word(Data(repeating: 1, count: 32)), .dynamic(Data("avatar".utf8)), .dynamic(Data("https://example.org/a.png".utf8))])
        let bytes = try CanonicalBytes.hex(data, count: (data.count - 2) / 2)
        XCTAssertEqual(bytes.subdata(in: 36..<68), EthereumABI.word(96))
        XCTAssertEqual(bytes.subdata(in: 68..<100), EthereumABI.word(160))
        for name in ["a..eth", "A.eth", "-a.eth", "a-.eth", "日本.eth", String(repeating: "a", count: 64) + ".eth"] {
            XCTAssertThrowsError(try EthereumABI.dns(name))
        }
        XCTAssertEqual(try EthereumABI.dns("a.eth"), Data([1,97,3,101,116,104,0]))
    }
}
