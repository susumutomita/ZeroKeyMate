import XCTest
@testable import ZeroKeyMate

final class ConnectionConfigurationTests:XCTestCase {
    func testArcCannotReuseSepoliaTokenAndUnsupportedChainsCannotSign() {
        var config=AppConfiguration(apiURL:"https://api.example.com",apiToken:String(repeating:"a",count:32),
            privyAppID:"",privyClientID:"",rpcURL:"https://rpc.testnet.arc.network",
            vault:"0x"+String(repeating:"11",count:20),token:"0x3600000000000000000000000000000000000000",chainID:5_042_002)
        XCTAssertTrue(config.paymentsConfigured)
        let arcKey=config.stateKey("pending-execution")
        config.chainID=11_155_111
        XCTAssertFalse(config.paymentsConfigured)
        XCTAssertNotEqual(config.stateKey("pending-execution"),arcKey)
        config.token=config.expectedToken!
        XCTAssertTrue(config.paymentsConfigured)
        config.chainID=1
        XCTAssertFalse(config.paymentsConfigured)
    }
}
