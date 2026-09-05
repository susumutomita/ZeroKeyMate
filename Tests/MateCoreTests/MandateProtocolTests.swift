import Foundation
import XCTest
@testable import MateCore

final class MandateProtocolTests: XCTestCase {
    func testAmountsAreExact() throws {
        for (text, units) in [("1",1_000_000 as UInt64),("0.000001",1),("5.25",5_250_000),("18446744073709.551615",UInt64.max)] {
            XCTAssertEqual(try TokenAmount(decimal:text).units,units)
        }
        XCTAssertEqual(TokenAmount(units:5_250_000).display,"5.25")
        XCTAssertEqual(TokenAmount(units:0).display,"0")
    }
    func testInvalidAmountsAreRejected() {
        for text in ["", "0", "-1", "+1", "1e6", "1,000", " 1", "1 ", "01", ".1", "1.", "1.0000001", "NaN", "１", "18446744073709.551616"] {
            XCTAssertThrowsError(try TokenAmount(decimal:text),text)
        }
    }
    func testHexRejectsUnicodeWhitespaceAndWrongLength() {
        for text in ["11", "0x1", "0xgg", "0x 1", "0x１", "0X11"] {
            XCTAssertThrowsError(try CanonicalBytes.hex(text,count:1))
        }
        XCTAssertEqual(try CanonicalBytes.hex("0xaF",count:1),Data([175]))
    }
    func testPolicyPreimageHasOneCanonicalEncoding() throws {
        let policy = try PrivatePolicy(budget:5_000_000,services:3,salt:Data(0..<32))
        let bytes = try policy.material()
        XCTAssertEqual(bytes.count,49)
        XCTAssertEqual(String(decoding:bytes.prefix(8),as:UTF8.self),"ZKM-POL1")
        XCTAssertEqual(bytes.subdata(in:8..<16),CanonicalBytes.u64(5_000_000))
        XCTAssertEqual(bytes[16],3)
        XCTAssertEqual(bytes.suffix(32),Data(0..<32))
    }
    func testLocalGuardDoesNotOverflow() throws {
        let p = try PrivatePolicy(budget:UInt64.max,services:1,salt:Data(repeating:7,count:32))
        XCTAssertNoThrow(try p.check(spent:UInt64.max-1,amount:1,service:.translation))
        XCTAssertThrowsError(try p.check(spent:UInt64.max,amount:1,service:.translation))
        XCTAssertThrowsError(try p.check(spent:0,amount:1,service:.summary))
        XCTAssertThrowsError(try p.check(spent:0,amount:0,service:.translation))
    }
    func testActionPreimageMatchesPublishedLayout() throws {
        let action=MandateAction(mandateId:"0x"+String(repeating:"22",count:32),recipient:"0x"+String(repeating:"33",count:20),
            amount:3_000_000,service:.translation,nonce:"0x"+String(repeating:"44",count:32),expiresAt:2_000_000_000,
            requestHash:"0x"+String(repeating:"55",count:32),spentBefore:0)
        let vault="0x"+String(repeating:"11",count:20)
        let bytes=try action.material(chainID:11_155_111,vault:vault)
        XCTAssertEqual(bytes.count,177)
        XCTAssertEqual(try action.context(chainID:11_155_111,vault:vault).count,160)
        XCTAssertEqual(bytes.subdata(in:160..<168),CanonicalBytes.u64(0))
        XCTAssertEqual(bytes.subdata(in:168..<176),CanonicalBytes.u64(3_000_000))
        XCTAssertEqual(bytes[176],0)
        XCTAssertNotEqual(bytes,try action.material(chainID:1,vault:vault))
    }
    func testSigningDocumentBindsDomainAndAllGrantFields() throws {
        let owner="0x"+String(repeating:"11",count:20), agent="0x"+String(repeating:"22",count:20), vault="0x"+String(repeating:"33",count:20)
        let grant=try MandateGrant(owner:owner,agent:agent,policyHash:"0x"+String(repeating:"44",count:32),validUntil:2_000_000_000,nonce:"0")
        let text=try SigningDocument.grant(grant,chainID:11_155_111,vault:vault)
        let parsed=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(text.utf8)) as? [String:Any])
        XCTAssertEqual(parsed["primaryType"] as? String,"Grant")
        let domain=try XCTUnwrap(parsed["domain"] as? [String:String])
        XCTAssertEqual(domain["chainId"],"11155111");XCTAssertEqual(domain["verifyingContract"],vault)
        let message=try XCTUnwrap(parsed["message"] as? [String:String])
        XCTAssertEqual(message["owner"],owner);XCTAssertEqual(message["agent"],agent)
    }
}
