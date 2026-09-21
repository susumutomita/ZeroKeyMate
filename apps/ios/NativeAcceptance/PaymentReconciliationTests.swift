import Foundation
import XCTest
import MateCore
@testable import ZeroKeyMate

private enum ReconciliationFixture {
    static let transaction="0x"+String(repeating:"aa",count:32)
    static let blockHash="0x"+String(repeating:"bb",count:32)
    static let checkpointHash="0x"+String(repeating:"cc",count:32)
    static let payer="0x"+String(repeating:"11",count:20)
    static let recipient="0x"+String(repeating:"22",count:20)
    static let nonce="0x"+String(repeating:"33",count:32)
    static func block(_ tag:String)->[String:Any] {
        ["number":tag,"hash":tag=="0xa" ? blockHash:checkpointHash,"timestamp":"0x3f2","transactions":[transaction]]
    }
    static func receipt()->[String:Any] {
        let from="0x"+String(repeating:"0",count:24)+String(payer.dropFirst(2))
        let to="0x"+String(repeating:"0",count:24)+String(recipient.dropFirst(2))
        let metadata:[String:Any]=["address":AgeShopProtocol.token,"transactionHash":transaction,"blockHash":blockHash,
            "blockNumber":"0xa","transactionIndex":"0x0","removed":false]
        var used=metadata,transfer=metadata
        used["topics"]=["0x98de503528ee59b575ef0c0a2576a82497bfc029a5685b209e9ec333479b10a5",from,nonce]
        used["data"]="0x";used["logIndex"]="0x2"
        transfer["topics"]=["0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef",from,to]
        transfer["data"]="0x"+String(repeating:"0",count:60)+"c350";transfer["logIndex"]="0x3"
        return ["transactionHash":transaction,"blockHash":blockHash,"blockNumber":"0xa","transactionIndex":"0x0",
                "status":"0x1","logs":[used,transfer]]
    }
    static func payment() throws -> PendingPayment {
        let service=try PaymentService(resource:"https://external-payment.invalid/resource",recipient:recipient,maximumAmount:100_000)
        let wire:[String:Any]=["x402Version":2,"resource":["url":service.resource],"accepts":[[
            "scheme":"exact","network":AgeShopProtocol.network,"amount":"50000","asset":AgeShopProtocol.token,
            "payTo":recipient,"maxTimeoutSeconds":60,"extra":["name":"USDC","version":"2"]]]]
        let request=try PaymentRequest.parse(header:JSONSerialization.data(withJSONObject:wire).base64EncodedString(),service:service,now:1000)
        let auth=try PaymentAuthorization(request:request,payer:payer,nonce:nonce,now:1001)
        return try PendingPayment(request:request,authorization:auth,signature:"0x"+String(repeating:"44",count:65),now:1001)
    }
    static func claim(_ pending:PendingPayment) throws -> PaymentReceipt {
        let value:[String:Any]=["success":false,"errorReason":"settlement_pending","transaction":transaction,
                                "network":AgeShopProtocol.network,"payer":payer]
        return try PaymentReceipt.parse(header:JSONSerialization.data(withJSONObject:value).base64EncodedString(),pending:pending,now:2000)
    }
}

private final class ReconciliationTrace:@unchecked Sendable {
    private let lock=NSLock()
    private var mode="",requests:[URLRequest]=[],checkpointReads=0
    func reset(_ mode:String){lock.lock();defer{lock.unlock()};self.mode=mode;requests=[];checkpointReads=0}
    func record(_ request:URLRequest,tag:String?)->(String,Int) {
        lock.lock();defer{lock.unlock()};requests.append(request)
        if tag=="0xb"{checkpointReads+=1}
        return (mode,checkpointReads)
    }
    func snapshot()->[URLRequest]{lock.lock();defer{lock.unlock()};return requests}
}
private final class ReconciliationHTTP:URLProtocol,@unchecked Sendable {
    static let trace=ReconciliationTrace()
    override class func canInit(with request:URLRequest)->Bool{true} // Intercept every test request; never use live RPCs.
    override class func canonicalRequest(for request:URLRequest)->URLRequest{request}
    override func startLoading() {
        do {
            var data=request.httpBody ?? Data()
            if let stream=request.httpBodyStream {
                stream.open();defer{stream.close()}
                var buffer=[UInt8](repeating:0,count:4096)
                while stream.hasBytesAvailable {let count=stream.read(&buffer,maxLength:buffer.count);if count<=0{break};data.append(contentsOf:buffer.prefix(count))}
            }
            let query=try JSONSerialization.jsonObject(with:data) as! [String:Any]
            let method=query["method"] as! String,params=query["params"] as! [Any]
            let tag=method=="eth_getBlockByNumber" ? params.first as? String:nil
            let(mode,reads)=Self.trace.record(request,tag:tag)
            if mode=="timeout"{throw URLError(.timedOut)}
            if mode=="waiting"{return} // A pending request that the task must cancel.
            let secondary=request.url!.host!.contains("drpc")
            var result:Any=NSNull()
            switch method {
            case "eth_chainId":result=mode=="wrong-chain" && secondary ? "0x1":"0x4cef52"
            case "eth_getBlockByNumber":
                let number=tag=="finalized" ? (secondary ? "0xb":"0xc"):tag!
                var block=ReconciliationFixture.block(number)
                if mode=="finalized-hash-disagreement" && secondary && tag=="finalized"{block["hash"]=ReconciliationFixture.blockHash}
                if tag=="finalized" && reads>2 {
                    if mode=="finalized-regression" && secondary{block=ReconciliationFixture.block("0xa")}
                    if mode=="primary-finalized-regression" && !secondary{block=ReconciliationFixture.block("0xb")}
                    if mode=="finalized-replaced" && secondary{block["hash"]=ReconciliationFixture.blockHash}
                    if mode=="finalized-new-head-disagreement"{
                        block=ReconciliationFixture.block("0xd")
                        if secondary{block["hash"]=ReconciliationFixture.blockHash}
                    }
                }
                if mode=="checkpoint-disagreement" && secondary && number=="0xb"{block["hash"]=ReconciliationFixture.blockHash}
                if mode=="checkpoint-changed" && reads>2 && number=="0xb"{block["hash"]=ReconciliationFixture.blockHash}
                if mode=="reorg" && number=="0xa"{block["hash"]=ReconciliationFixture.checkpointHash}
                if mode=="absent-transaction" && number=="0xa"{block["transactions"]=[]}
                if mode=="expired-before-mining" && number=="0xa"{block["timestamp"]="0x425"}
                if mode=="wrong-number" && number=="0xa"{block["number"]="0x9"}
                if mode=="malformed-quantity"{block["number"]="0x0b"}
                if mode=="future-receipt" && tag=="finalized"{block=ReconciliationFixture.block("0x9")}
                result=block
            case "eth_getTransactionReceipt":
                var receipt=ReconciliationFixture.receipt()
                if mode=="reverted"{receipt["status"]="0x0"}
                if mode=="wrong-hash"{receipt["transactionHash"]=ReconciliationFixture.checkpointHash}
                if mode=="receipt-disagreement" && secondary{receipt["transactionIndex"]="0x1"}
                var logs=receipt["logs"] as! [[String:Any]]
                if mode=="removed"{logs[0]["removed"]=true}
                if mode=="wrong-log-transaction"{logs[0]["transactionHash"]=ReconciliationFixture.checkpointHash}
                if mode=="wrong-log-block"{logs[0]["blockNumber"]="0x9"}
                if mode=="duplicate-log-index"{logs[1]["logIndex"]="0x2"}
                if mode=="wrong-token"{logs[0]["address"]=ReconciliationFixture.recipient}
                if mode=="wrong-amount"{logs[1]["data"]="0x"+String(repeating:"0",count:64)}
                if mode=="canceled"{var topics=logs[0]["topics"] as! [String];topics[0]="0x1cdd46ff242716cdaa72d159d339a485b3438398348d68f09d7c8c0a59353d81";logs[0]["topics"]=topics}
                receipt["logs"]=logs;result=mode=="null-receipt" && secondary ? NSNull():receipt
            default:throw ExternalPaymentError.invalidReceipt
            }
            var reply:[String:Any]=["jsonrpc":"2.0","id":mode=="wrong-id" ? 2:1,"result":result]
            if mode=="rpc-error"{reply["error"]=["code":-32000,"message":"fixture"]}
            let body=mode=="oversize" ? Data(repeating:65,count:1_048_577):try JSONSerialization.data(withJSONObject:reply)
            let response=HTTPURLResponse(url:request.url!,statusCode:mode=="redirect" ? 307:200,httpVersion:nil,
                headerFields:["Location":"https://untrusted.invalid/","Set-Cookie":"session=fixture"])!
            client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
            client?.urlProtocol(self,didLoad:body);client?.urlProtocolDidFinishLoading(self)
        }catch{client?.urlProtocol(self,didFailWithError:error)}
    }
    override func stopLoading(){}
}
private actor ReconciliationJournal:PaymentJournal {
    private var pending:PendingPayment?
    init(_ pending:PendingPayment){self.pending=pending}
    func load()->PendingPayment?{pending}
    func reserve(_ value:PendingPayment) throws {
        guard value==pending else{throw ExternalPaymentError.unresolvedPayment}
    }
}

final class PaymentReconciliationTests:XCTestCase {
    private func checker(_ mode:String="")->ExternalPaymentReconciliation {
        ReconciliationHTTP.trace.reset(mode)
        let c=URLSessionConfiguration.ephemeral;c.protocolClasses=[ReconciliationHTTP.self]
        c.httpAdditionalHeaders=["Authorization":"must-not-send","Cookie":"must-not-send","PAYMENT-SIGNATURE":"must-not-send"]
        return ExternalPaymentReconciliation(configuration:c)
    }
    func testConfirmedTransferAfterExpiryUsesTheCommonFinalizedBlock() async throws {
        let pending=try ReconciliationFixture.payment(),journal=ReconciliationJournal(pending)
        let recovery=ExternalPaymentRecovery(journal:journal)
        let result=try await recovery.reconcile(using:checker(),claim:ReconciliationFixture.claim(pending),now:2000)
        guard case let .confirmed(evidence)=result else{return XCTFail("Expected corroborated settlement")}
        XCTAssertEqual(evidence.transaction,ReconciliationFixture.transaction)
        XCTAssertEqual(evidence.blockNumber,10);XCTAssertEqual(evidence.checkpointNumber,11)
        let retained=await journal.load();XCTAssertEqual(retained,pending,"Evidence alone never releases the journal")
        let requests=ReconciliationHTTP.trace.snapshot();XCTAssertEqual(requests.count,14)
        XCTAssertEqual(Set(requests.compactMap{$0.url?.host}),["rpc.testnet.arc.io","rpc.drpc.testnet.arc.io"])
        for request in requests {
            XCTAssertEqual(request.httpMethod,"POST")
            for header in ["Authorization","Cookie","PAYMENT-SIGNATURE"]{XCTAssertNil(request.value(forHTTPHeaderField:header))}
        }
    }
    func testContradictoryIncompleteAndNoncanonicalEvidenceNeverMeansUnpaid() async throws {
        let pending=try ReconciliationFixture.payment(),claim=try ReconciliationFixture.claim(pending)
        for mode in ["wrong-chain","checkpoint-disagreement","finalized-hash-disagreement","checkpoint-changed",
                     "finalized-regression","primary-finalized-regression","finalized-replaced","finalized-new-head-disagreement","reorg","absent-transaction",
                     "expired-before-mining","wrong-number","malformed-quantity","future-receipt","reverted","wrong-hash",
                     "receipt-disagreement","null-receipt"] {
            let result=try await checker(mode).reconcile(pending,claim:claim,now:2000)
            XCTAssertEqual(result,.unresolved,mode)
        }
    }
    func testTamperedOrCanceledAuthorizationLogsCannotEstablishSettlement() async throws {
        let pending=try ReconciliationFixture.payment(),claim=try ReconciliationFixture.claim(pending)
        for mode in ["removed","wrong-log-transaction","wrong-log-block","duplicate-log-index","wrong-token","wrong-amount","canceled"] {
            let result=try await checker(mode).reconcile(pending,claim:claim,now:2000)
            XCTAssertEqual(result,.unresolved,mode)
        }
    }
    func testTransportFailuresAndMissingLocatorRetainTheJournal() async throws {
        let pending=try ReconciliationFixture.payment(),journal=ReconciliationJournal(pending)
        let recovery=ExternalPaymentRecovery(journal:journal)
        for mode in ["timeout","wrong-id","rpc-error","oversize","redirect"] {
            let result=try await recovery.reconcile(using:checker(mode),claim:ReconciliationFixture.claim(pending),now:2000)
            XCTAssertEqual(result,.unresolved,mode)
            let saved=await journal.load();XCTAssertEqual(saved,pending)
            XCTAssertEqual(ReconciliationHTTP.trace.snapshot().count,1)
        }
        let result=try await recovery.reconcile(using:checker(),claim:nil,now:2000)
        XCTAssertEqual(result,.unresolved);XCTAssertTrue(ReconciliationHTTP.trace.snapshot().isEmpty)
    }
    func testCancellationDoesNotGetConvertedIntoAnUnpaidResult() async throws {
        let pending=try ReconciliationFixture.payment(),checker=checker(),claim=try ReconciliationFixture.claim(pending)
        let task=Task {
            withUnsafeCurrentTask{$0?.cancel()}
            return try await checker.reconcile(pending,claim:claim,now:2000)
        }
        do{_ = try await task.value;XCTFail("Expected cancellation")}catch is CancellationError{}
        XCTAssertTrue(ReconciliationHTTP.trace.snapshot().isEmpty)
    }
    func testCancellationDuringRPCStopsFurtherReadsAndRetainsJournal() async throws {
        let pending=try ReconciliationFixture.payment(),journal=ReconciliationJournal(pending)
        let recovery=ExternalPaymentRecovery(journal:journal),checker=checker("waiting")
        let claim=try ReconciliationFixture.claim(pending)
        let task=Task{try await recovery.reconcile(using:checker,claim:claim,now:2000)}
        for _ in 0..<200 {
            if !ReconciliationHTTP.trace.snapshot().isEmpty{break}
            try await Task.sleep(for:.milliseconds(10))
        }
        task.cancel()
        do{_ = try await task.value;XCTFail("Expected cancellation")}catch is CancellationError{}
        XCTAssertEqual(ReconciliationHTTP.trace.snapshot().count,1)
        let saved=await journal.load();XCTAssertEqual(saved,pending)
    }
}
