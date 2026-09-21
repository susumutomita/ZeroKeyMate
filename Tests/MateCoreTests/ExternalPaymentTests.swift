import XCTest
@testable import MateCore

final class ExternalPaymentTests:XCTestCase {
    private let payer="0x"+String(repeating:"11",count:20)
    private let recipient="0x"+String(repeating:"22",count:20)
    private let nonce="0x"+String(repeating:"33",count:32)
    private let signature="0x"+String(repeating:"44",count:65) // serialization fixture; never broadcast
    private func service(_ resource:String="https://api.example.com/data") throws -> PaymentService {
        try PaymentService(resource:resource,recipient:recipient,maximumAmount:100_000)
    }
    private func challenge() -> [String:Any] {
        ["x402Version":2,"resource":["url":"https://api.example.com/data"],"accepts":[[
            "scheme":"exact","network":"eip155:5042002","amount":"50000",
            "asset":AgeShopProtocol.token,"payTo":recipient,"maxTimeoutSeconds":60,
            "extra":["name":"USDC","version":"2"]]],"extensions":[:]]
    }
    private func header(_ value:[String:Any]) throws -> String {try JSONSerialization.data(withJSONObject:value).base64EncodedString()}
    private func request(_ value:[String:Any]?=nil) throws -> PaymentRequest {
        try PaymentRequest.parse(header:header(value ?? challenge()),service:service(),now:1_000)
    }
    private func pending() throws -> PendingPayment {
        let r=try request(),a=try PaymentAuthorization(request:r,payer:payer,nonce:nonce,now:1_001)
        return try PendingPayment(request:r,authorization:a,signature:signature,now:1_001)
    }
    func testStandardV2QuoteAndEIP3009PayloadRoundTrip() throws {
        let r=try request();XCTAssertEqual(r.accepted.amount,"50000");XCTAssertEqual(r.expiresAt,1060)
        let p=try pending(),wire=try p.header(now:1_002)
        let decoded=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(base64Encoded:wire)!) as? [String:Any])
        XCTAssertEqual(decoded["x402Version"] as? Int,2)
        XCTAssertEqual((decoded["resource"] as? [String:String])?["url"],"https://api.example.com/data")
        let payload=try XCTUnwrap(decoded["payload"] as? [String:Any])
        let auth=try XCTUnwrap(payload["authorization"] as? [String:String])
        XCTAssertEqual(auth,["from":payer,"to":recipient,"value":"50000","nonce":nonce,"validAfter":"0","validBefore":"1061"])
        let saved=try JSONEncoder().encode(p),restored=try JSONDecoder().decode(PendingPayment.self,from:saved)
        XCTAssertEqual(try restored.header(now:1_020),wire,"A retry must not produce a fresh nonce, deadline or signature")
    }
    func testChallengeRejectsEveryUnsupportedFinancialField() throws {
        let changes:[String:Any]=["scheme":"upto","network":"eip155:1","asset":payer,"payTo":payer,
            "amount":"100001","maxTimeoutSeconds":301,"extra":["name":"USDC","version":"1"]]
        for(key,value) in changes {
            var c=challenge(),a=(c["accepts"] as! [[String:Any]])[0];a[key]=value;c["accepts"]=[a]
            XCTAssertThrowsError(try request(c),key)
        }
        for value in ["0","-1","+50000","050000","0.05","1e5","18446744073709551616"] {
            var c=challenge(),a=(c["accepts"] as! [[String:Any]])[0];a["amount"]=value;c["accepts"]=[a]
            XCTAssertThrowsError(try request(c),value)
        }
        for extra in [["name":"USDC","version":"2","assetTransferMethod":"permit2"],
                      ["name":"USDC","version":"2","paymentFlow":"payable"],
                      ["name":"USDC","version":"2","unreviewed":"value"]] {
            var c=challenge(),a=(c["accepts"] as! [[String:Any]])[0];a["extra"]=extra;c["accepts"]=[a]
            XCTAssertThrowsError(try request(c))
        }
    }
    func testChallengeCannotRedirectResourceAddExtensionsOrChooseAmbiguousPrices() throws {
        for(key,value) in [("x402Version",1 as Any),("resource",["url":"https://other.example/data"]),
                           ("extensions",["unknown":["info":"value"]]),("accepts",[])] {
            var c=challenge();c[key]=value;XCTAssertThrowsError(try request(c))
        }
        var c=challenge();let accepted=c["accepts"] as! [[String:Any]];c["accepts"]=accepted+accepted
        XCTAssertThrowsError(try request(c))
        XCTAssertThrowsError(try PaymentRequest.parse(header:String(repeating:"A",count:16_385),service:service(),now:1000))
        XCTAssertThrowsError(try PaymentRequest.parse(header:"not-base64",service:service(),now:1000))
    }
    func testRegisteredServiceRejectsCredentialsLocalIPsQueriesAndNormalization() throws {
        for url in ["http://api.example.com/data","https://user:pass@api.example.com/data","https://127.0.0.1/data",
                    "https://0x7f.0.0.1/data","https://0177.0.0.1/data","https://127.1/data",
                    "https://[::1]/data","https://localhost/data","https://shop.local/data","https://api.example.com:443/data",
                    "https://api.example.com/data?secret=x","https://api.example.com/data#fragment","https://api.example.com/%2fdata",
                    "https://api.example.com/../data","file:///tmp/data"] {
            XCTAssertThrowsError(try service(url),url)
        }
        XCTAssertThrowsError(try PaymentService(resource:"https://api.example.com/data",recipient:recipient,maximumAmount:500_001))
    }
    func testExpiredPaymentsRemainReadableButCannotBeResubmittedOrSignedAgain() throws {
        let p=try pending()
        XCTAssertThrowsError(try p.header(now:1061))
        XCTAssertNoThrow(try p.validate(now:2000,allowExpired:true))
        XCTAssertThrowsError(try PaymentAuthorization(request:p.request,payer:payer,nonce:nonce,now:1060))
        var data=try JSONSerialization.jsonObject(with:JSONEncoder().encode(p)) as! [String:Any]
        var a=data["authorization"] as! [String:Any];a["value"]="1";data["authorization"]=a
        let tampered=try JSONDecoder().decode(PendingPayment.self,from:JSONSerialization.data(withJSONObject:data))
        XCTAssertThrowsError(try tampered.header(now:1002))
        var r=try JSONSerialization.jsonObject(with:JSONEncoder().encode(p.request)) as! [String:Any];r["quotedAt"]=0
        let broken=try JSONDecoder().decode(PaymentRequest.self,from:JSONSerialization.data(withJSONObject:r))
        XCTAssertThrowsError(try p.authorization.validate(request:broken),"Malformed persisted data must not underflow")
    }
    func testApprovalDeadlineDoesNotShortenTheAdvertisedSettlementWindow() throws {
        var c=challenge(),a=(c["accepts"] as! [[String:Any]])[0]
        a["maxTimeoutSeconds"]=300;c["accepts"]=[a]
        let r=try request(c);XCTAssertEqual(r.expiresAt,1180)
        let auth=try PaymentAuthorization(request:r,payer:payer,nonce:nonce,now:1179)
        XCTAssertEqual(auth.validBefore,"1479")
        let p=try PendingPayment(request:r,authorization:auth,signature:signature,now:1179)
        XCTAssertNoThrow(try p.header(now:1300),"Retry an already-approved payment after the quote's approval deadline")
        XCTAssertThrowsError(try p.header(now:1479))
        XCTAssertThrowsError(try PendingPayment(request:r,authorization:auth,signature:signature,now:1180),"Do not approve a new payment from an expired quote")
    }
    func testServerSuccessIsOnlyAClaimAndRequiresBothTransferAndAuthorizationEvidence() throws {
        let p=try pending(),hash="0x"+String(repeating:"aa",count:32)
        let wire:[String:Any]=["success":true,"transaction":hash,"network":AgeShopProtocol.network,"payer":payer]
        let r=try PaymentReceipt.parse(header:header(wire),pending:p,now:2000)
        let from="0x"+String(repeating:"0",count:24)+String(payer.dropFirst(2))
        let to="0x"+String(repeating:"0",count:24)+String(recipient.dropFirst(2))
        let transfer=AgeShopReceipt.Log(address:AgeShopProtocol.token,
            topics:["0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef",from,to],
            data:"0x"+String(repeating:"0",count:60)+"c350")
        let used=AgeShopReceipt.Log(address:AgeShopProtocol.token,
            topics:["0x98de503528ee59b575ef0c0a2576a82497bfc029a5685b209e9ec333479b10a5",from,nonce],data:"0x")
        XCTAssertThrowsError(try r.validateTransfer(pending:p,logs:[],now:2000))
        XCTAssertThrowsError(try r.validateTransfer(pending:p,logs:[transfer],now:2000))
        XCTAssertThrowsError(try r.validateTransfer(pending:p,logs:[used],now:2000))
        XCTAssertNoThrow(try r.validateTransfer(pending:p,logs:[used,transfer],now:2000))
        XCTAssertThrowsError(try r.validateTransfer(pending:p,logs:[transfer,used],now:2000))
        let wrong=AgeShopReceipt.Log(address:AgeShopProtocol.token,topics:transfer.topics,data:"0x"+String(repeating:"0",count:64))
        XCTAssertThrowsError(try r.validateTransfer(pending:p,logs:[used,wrong,transfer],now:2000),"Do not pair a nonce with an unrelated later transfer")
        let canceled=AgeShopReceipt.Log(address:AgeShopProtocol.token,
            topics:["0x1cdd46ff242716cdaa72d159d339a485b3438398348d68f09d7c8c0a59353d81",from,nonce],data:"0x")
        XCTAssertThrowsError(try r.validateTransfer(pending:p,logs:[used,transfer,canceled],now:2000))
        XCTAssertThrowsError(try r.validateTransfer(pending:p,logs:[used,transfer,used,transfer],now:2000))
        var pendingClaim=wire;pendingClaim["success"]=false;pendingClaim["errorReason"]="settlement_pending"
        XCTAssertFalse(try PaymentReceipt.parse(header:header(pendingClaim),pending:p,now:2000).success)
        pendingClaim["success"]=true
        XCTAssertThrowsError(try PaymentReceipt.parse(header:header(pendingClaim),pending:p,now:2000))
        for(key,value) in [("network","eip155:1"),("payer",recipient),("transaction","not-a-hash")] {
            var bad=wire;bad[key]=value;XCTAssertThrowsError(try PaymentReceipt.parse(header:header(bad),pending:p,now:2000))
        }
    }
}
