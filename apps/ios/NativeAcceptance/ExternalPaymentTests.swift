import Foundation
import XCTest
import MateCore
@testable import ZeroKeyMate

private final class PaymentHTTPTrace:@unchecked Sendable {
    private let lock=NSLock()
    private var values:[URLRequest]=[]
    func append(_ value:URLRequest){lock.lock();defer{lock.unlock()};values.append(value)}
    func reset(){lock.lock();defer{lock.unlock()};values=[]}
    func snapshot()->[URLRequest]{lock.lock();defer{lock.unlock()};return values}
}
private final class PaymentHTTPFixture:URLProtocol,@unchecked Sendable {
    static let trace=PaymentHTTPTrace()
    override class func canInit(with request:URLRequest)->Bool{request.url?.host=="external-payment.invalid"}
    override class func canonicalRequest(for request:URLRequest)->URLRequest{request}
    override func startLoading(){
        Self.trace.append(request)
        if request.url!.path=="/timeout"{client?.urlProtocol(self,didFailWithError:URLError(.timedOut));return}
        let code=request.url!.path=="/redirect" ? 302 : 402
        let body=request.url!.path=="/oversize" ? Data(repeating:65,count:65_537) : Data("{}".utf8)
        let c:[String:Any]=["x402Version":2,"resource":["url":request.url!.absoluteString],"accepts":[[
            "scheme":"exact","network":AgeShopProtocol.network,"amount":"50000","asset":AgeShopProtocol.token,
            "payTo":"0x"+String(repeating:"22",count:20),"maxTimeoutSeconds":60,"extra":["name":"USDC","version":"2"]]]]
        let header=try! JSONSerialization.data(withJSONObject:c).base64EncodedString()
        let response=HTTPURLResponse(url:request.url!,statusCode:code,httpVersion:nil,
            headerFields:["PAYMENT-REQUIRED":header,"Location":"https://other.invalid/steal","Set-Cookie":"session=fixture"])!
        client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:body);client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading(){}
}
private actor MemoryPaymentJournal:PaymentJournal {
    private var pending:PendingPayment?
    private let unavailable:Bool
    init(unavailable:Bool=false){self.unavailable=unavailable}
    func load()->PendingPayment?{pending}
    func reserve(_ value:PendingPayment) throws {
        if unavailable{throw URLError(.cannotWriteToFile)}
        if let pending{guard pending==value else{throw ExternalPaymentError.unresolvedPayment}}
        else{pending=value}
    }
}

final class ExternalPaymentTransportTests:XCTestCase {
    override func setUp(){PaymentHTTPFixture.trace.reset()}
    private func service(_ path:String) throws -> PaymentService {
        try PaymentService(resource:"https://external-payment.invalid/"+path,
                           recipient:"0x"+String(repeating:"22",count:20),maximumAmount:100_000)
    }
    private func client(_ path:String) throws -> ExternalPaymentClient {
        let c=URLSessionConfiguration.ephemeral;c.protocolClasses=[PaymentHTTPFixture.self]
        c.httpAdditionalHeaders=["Authorization":"must-not-send","Cookie":"must-not-send"]
        return try ExternalPaymentClient(service:service(path),configuration:c)
    }
    private func payment(_ path:String,nonce:String=String(repeating:"33",count:32)) throws -> PendingPayment {
        let s=try service(path)
        let wire:[String:Any]=["x402Version":2,"resource":["url":s.resource],"accepts":[[
            "scheme":"exact","network":AgeShopProtocol.network,"amount":"50000","asset":AgeShopProtocol.token,
            "payTo":s.recipient,"maxTimeoutSeconds":60,"extra":["name":"USDC","version":"2"]]]]
        let r=try PaymentRequest.parse(header:JSONSerialization.data(withJSONObject:wire).base64EncodedString(),service:s,now:1000)
        let a=try PaymentAuthorization(request:r,payer:"0x"+String(repeating:"11",count:20),nonce:"0x"+nonce,now:1001)
        return try PendingPayment(request:r,authorization:a,signature:"0x"+String(repeating:"44",count:65),now:1001)
    }
    func testQuoteIsARegisteredGETWithoutCookiesCredentialsOrSignature() async throws {
        let c=try client("quote"),quote=try await c.quote(now:1000)
        XCTAssertEqual(quote.accepted.amount,"50000")
        _=try await c.quote(now:1001)
        let requests=PaymentHTTPFixture.trace.snapshot();XCTAssertEqual(requests.count,2)
        for r in requests {
            XCTAssertEqual(r.httpMethod,"GET");XCTAssertNil(r.httpBody)
            XCTAssertNil(r.value(forHTTPHeaderField:"Authorization"));XCTAssertNil(r.value(forHTTPHeaderField:"Cookie"))
            XCTAssertNil(r.value(forHTTPHeaderField:"PAYMENT-SIGNATURE"))
        }
    }
    func testRedirectAndOversizeResponsesFailWithoutFollowingAnotherURL() async throws {
        for path in ["redirect","oversize"] {
            do{_ = try await client(path).quote(now:1000);XCTFail("Accepted \(path)")}catch{}
        }
        XCTAssertEqual(PaymentHTTPFixture.trace.snapshot().count,2)
        XCTAssertTrue(PaymentHTTPFixture.trace.snapshot().allSatisfy{$0.url?.host=="external-payment.invalid"})
    }
    func testTimeoutAndRestartRetryExactlyTheSameSignatureAndBlockNewPayments() async throws {
        let journal=MemoryPaymentJournal(),p=try payment("timeout"),c=try client("timeout")
        let first=ExternalPaymentRecovery(journal:journal)
        do{_ = try await first.submit(p,through:c,now:1002);XCTFail("Expected timeout")}catch{}
        let saved=await journal.load();XCTAssertEqual(saved,p)
        let afterRestart=ExternalPaymentRecovery(journal:journal)
        do{_ = try await afterRestart.submit(p,through:c,now:1003);XCTFail("Expected timeout")}catch{}
        let changed=try payment("timeout",nonce:String(repeating:"55",count:32))
        do{_ = try await afterRestart.submit(changed,through:c,now:1003);XCTFail("Signed replacement was accepted")}
        catch{XCTAssertEqual(error as? ExternalPaymentError,.unresolvedPayment)}
        let requests=PaymentHTTPFixture.trace.snapshot();XCTAssertEqual(requests.count,2)
        XCTAssertEqual(requests[0].value(forHTTPHeaderField:"PAYMENT-SIGNATURE"),requests[1].value(forHTTPHeaderField:"PAYMENT-SIGNATURE"))
        do{_ = try await afterRestart.submit(p,through:c,now:1100);XCTFail("Expired retry was sent")}catch{}
        let retained=await journal.load();XCTAssertEqual(retained,p)
        XCTAssertEqual(PaymentHTTPFixture.trace.snapshot().count,2)
    }
    func testPersistenceFailureAndEndpointMismatchCannotSendPayment() async throws {
        let p=try payment("quote"),failed=ExternalPaymentRecovery(journal:MemoryPaymentJournal(unavailable:true))
        do{_ = try await failed.submit(p,through:client("quote"),now:1002);XCTFail("Unstored signature was sent")}catch{}
        do{_ = try await client("other").submit(p,now:1002);XCTFail("Signature leaked to another endpoint")}catch{}
        XCTAssertTrue(PaymentHTTPFixture.trace.snapshot().isEmpty)
    }
    func testRejectedPaidResponsesRetainThePendingPayment() async throws {
        for path in ["redirect","oversize"] {
            let journal=MemoryPaymentJournal(),recovery=ExternalPaymentRecovery(journal:journal),p=try payment(path)
            do{_ = try await recovery.submit(p,through:client(path),now:1002);XCTFail("Expected rejected response")}
            catch{}
            let saved=await journal.load();XCTAssertEqual(saved,p,"A bad response after transmission is not evidence of nonpayment")
        }
        XCTAssertEqual(PaymentHTTPFixture.trace.snapshot().count,2)
    }
    func testTwoCoordinatorsCannotReserveDifferentPaymentsConcurrently() async throws {
        let journal=MemoryPaymentJournal(),first=ExternalPaymentRecovery(journal:journal),second=ExternalPaymentRecovery(journal:journal)
        let p=try payment("quote"),other=try payment("quote",nonce:String(repeating:"55",count:32)),c=try client("quote")
        await withTaskGroup(of:Void.self){group in
            group.addTask{_ = try? await first.submit(p,through:c,now:1002)}
            group.addTask{_ = try? await second.submit(other,through:c,now:1002)}
        }
        XCTAssertEqual(PaymentHTTPFixture.trace.snapshot().count,1)
        let saved=await journal.load();XCTAssertTrue(saved==p || saved==other)
    }
}
