import XCTest
@testable import MateCore

final class AgentDelegationTests:XCTestCase {
    let vault="0x"+String(repeating:"1",count:40)
    let recipient="0x"+String(repeating:"2",count:40)
    let mandate="0x"+String(repeating:"3",count:64)
    func testPermissionCannotExpandWithNewProviderChainMandateOrPrice() throws {
        let consent=AgentDelegation(chainID:5042002,vault:vault,mandateID:mandate,providerID:"11155111:1",recipient:recipient,service:0,maximumAmount:100000,validUntil:2000)
        func permits(chain:UInt64=5042002,contract:String?=nil,id:String?=nil,provider:String="11155111:1",payee:String?=nil,service:UInt8=0,amount:UInt64=100000,now:UInt64=1000)->Bool {
            consent.permits(chainID:chain,vault:contract ?? vault,mandateID:id ?? mandate,providerID:provider,recipient:payee ?? recipient,service:service,amount:amount,now:now)
        }
        XCTAssertTrue(permits());XCTAssertTrue(permits(amount:1))
        XCTAssertFalse(permits(chain:11155111));XCTAssertFalse(permits(contract:recipient))
        XCTAssertFalse(permits(id:"0x"+String(repeating:"4",count:64)))
        XCTAssertFalse(permits(provider:"11155111:2"));XCTAssertFalse(permits(payee:vault))
        XCTAssertFalse(permits(service:1));XCTAssertFalse(permits(amount:100001))
        XCTAssertFalse(permits(amount:0));XCTAssertFalse(permits(now:2000))
        XCTAssertEqual(try JSONDecoder().decode(AgentDelegation.self,from:JSONEncoder().encode(consent)),consent)
    }
}
