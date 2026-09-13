import XCTest
@testable import ZeroKeyMate

final class ConnectionConfigurationTests:XCTestCase {
    func testArcCannotReuseSepoliaTokenAndUnsupportedChainsCannotSign() {
        var config=AppConfiguration(apiURL:"https://api.example.com",apiToken:"session_"+String(repeating:"a",count:64),
            privyAppID:"",privyClientID:"",rpcURL:"https://rpc.testnet.arc.network",
            vault:"0x"+String(repeating:"11",count:20),token:"0x3600000000000000000000000000000000000000",chainID:5_042_002)
        config.apiTokenExpiresAt=UInt64(Date().timeIntervalSince1970)+3600
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
    func testRenewalRetainsEnvironmentButExpiredAndLegacyTokensCannotAuthorize() {
        var config=AppConfiguration(apiURL:"https://api.example.com",apiToken:"session_"+String(repeating:"a",count:64),
            privyAppID:"app",privyClientID:"client",rpcURL:"https://rpc.testnet.arc.network",
            vault:"0x"+String(repeating:"11",count:20),token:"0x3600000000000000000000000000000000000000",chainID:5_042_002)
        XCTAssertFalse(config.pairingValid)
        let previous=config
        config.apiTokenExpiresAt=UInt64(Date().timeIntervalSince1970)+3600
        XCTAssertTrue(config.pairingValid)
        XCTAssertTrue(config.sameEnvironment(as:previous))
        config.apiToken=String(repeating:"b",count:64)
        XCTAssertFalse(config.pairingValid)
        config.apiURL="https://other.example.com"
        XCTAssertFalse(config.sameEnvironment(as:previous))
        config=previous;config.vault="0x"+String(repeating:"22",count:20)
        XCTAssertFalse(config.sameEnvironment(as:previous))
        config=previous;config.privyAppID="another-app"
        XCTAssertFalse(config.sameEnvironment(as:previous))
    }
}

private final class PairingProtocol:URLProtocol,@unchecked Sendable {
    override class func canInit(with request:URLRequest) -> Bool {true}
    override class func canonicalRequest(for request:URLRequest) -> URLRequest {request}
    override func startLoading() {
        let path=request.url!.path
        let auth=request.value(forHTTPHeaderField:"Authorization")
        let session="session_"+String(repeating:"c",count:64)
        let publicRequest=path == "/v1/configuration" || path == "/v1/pair"
        let valid=publicRequest ? auth == nil : auth == "Bearer " + session
        let body:[String:Any]
        if path == "/v1/configuration" {
            body=["chainId":5_042_002,"vault":"0x"+String(repeating:"11",count:20),"token":"0x3600000000000000000000000000000000000000","actionVersion":"ZKM-ACT1"]
        } else if path == "/v1/pair" {
            body=["token":session,"expiresAt":UInt64(Date().timeIntervalSince1970)+3600,"remainingRequests":500]
        } else {body=["paired":true]}
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:valid ? 200:401,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:try! JSONSerialization.data(withJSONObject:body))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

extension ConnectionConfigurationTests {
    func testPublicValidationAndCodeExchangeNeverSendPreviouslySavedBearer() async throws {
        var config=AppConfiguration(apiURL:"https://api.example.com",apiToken:"old-private-token",
            privyAppID:"",privyClientID:"",rpcURL:"https://rpc.testnet.arc.network",
            vault:"0x"+String(repeating:"11",count:20),token:"0x3600000000000000000000000000000000000000",chainID:5_042_002)
        let settings=URLSessionConfiguration.ephemeral;settings.protocolClasses=[PairingProtocol.self]
        let service=NetworkService(configuration:config,sessionConfiguration:settings)
        try await service.validateDeployment()
        config=try await service.pair(code:"pair_"+String(repeating:"d",count:64))
        XCTAssertTrue(config.pairingValid)
        try await NetworkService(configuration:config,sessionConfiguration:settings).validatePairing()
        config.apiTokenExpiresAt=0
        do {
            try await NetworkService(configuration:config,sessionConfiguration:settings).validatePairing()
            XCTFail("Expired sessions must not authorize a request")
        } catch {}
    }
}
