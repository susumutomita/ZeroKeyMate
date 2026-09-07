import Foundation
import XCTest
@testable import MateCore

final class ExecutionEvidenceTests:XCTestCase {
    func testReceiptMustContainExactVaultEvent() throws {
        let vault="0x"+String(repeating:"11",count:20),hash="0x"+String(repeating:"22",count:32)
        let proof="0x"+String(repeating:"33",count:32),mandate="0x"+String(repeating:"44",count:32),nonce="0x"+String(repeating:"55",count:32)
        let action=MandateAction(mandateId:mandate,recipient:vault,amount:7,service:.translation,nonce:nonce,
            expiresAt:2_000_000_000,requestHash:hash,spentBefore:5)
        let topics=[ExecutionEvidence.topic,mandate,hash,nonce]
        func word(_ value:UInt64)->String{let hex=String(value,radix:16);return String(repeating:"0",count:64-hex.count)+hex}
        let data="0x"+String(repeating:"0",count:24)+vault.dropFirst(2)+word(7)+word(0)+proof.dropFirst(2)+word(12)
        func validate(_ address:String,_ topics:[String],_ data:String) throws {
            try ExecutionEvidence.validate(address:address,topics:topics,data:data,vault:vault,actionHash:hash,
                proofHash:proof,spentAfter:12,action:action)
        }
        XCTAssertNoThrow(try validate(vault,topics,data))
        XCTAssertThrowsError(try validate("0x"+String(repeating:"99",count:20),topics,data))
        for i in 0..<4{var altered=topics;altered[i]="0x"+String(repeating:"aa",count:32);XCTAssertThrowsError(try validate(vault,altered,data))}
        for index in [12,63,95,96,159] {
            var altered=try CanonicalBytes.hex(data,count:160);altered[index] ^= 1
            XCTAssertThrowsError(try validate(vault,topics,CanonicalBytes.hexString(altered)))
        }
        XCTAssertThrowsError(try validate(vault,topics,"0x"))
    }
}
