import Foundation
import MateCore

private final class ExternalPaymentRedirects:NSObject,URLSessionTaskDelegate,@unchecked Sendable {
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,
                    newRequest request:URLRequest,completionHandler:@escaping(URLRequest?)->Void){completionHandler(nil)}
}

/// GET transport for reviewed x402 endpoints. No wallet, model, card or signing
/// method is reachable here. The dedicated shop continues using AgeShopClient.
actor ExternalPaymentClient {
    struct Response:Sendable {let status:Int,body:Data,paymentRequired:String?,paymentResponse:String?}
    private let service:PaymentService?
    private let url:URL
    private let session:URLSession
    init(service:PaymentService,configuration:URLSessionConfiguration = .ephemeral) throws {
        url=try service.validate();self.service=service
        session=Self.session(configuration)
    }
    /// Read-only discovery: this client has no approved recipient, so cannot submit.
    init(resource:String,configuration:URLSessionConfiguration = .ephemeral) throws {
        url=try PaymentService.validateResource(resource);service=nil
        session=Self.session(configuration)
    }
    private static func session(_ configuration:URLSessionConfiguration) -> URLSession {
        let configuration=configuration.copy() as! URLSessionConfiguration
        configuration.httpShouldSetCookies=false;configuration.httpCookieStorage=nil
        configuration.urlCredentialStorage=nil;configuration.urlCache=nil
        configuration.httpAdditionalHeaders=[:];configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest=30;configuration.timeoutIntervalForResource=45
        return URLSession(configuration:configuration,delegate:ExternalPaymentRedirects(),delegateQueue:nil)
    }
    deinit{session.invalidateAndCancel()}
    func quote(now:UInt64) async throws -> PaymentRequest {
        guard let service else{throw ExternalPaymentError.invalidService}
        let result=try await get(payment:nil)
        guard result.status==402,let header=result.paymentRequired else{throw ExternalPaymentError.invalidChallenge}
        return try PaymentRequest.parse(header:header,service:service,now:now)
    }
    func discover(maximumAmount:UInt64,now:UInt64) async throws -> PaymentRequest {
        guard service==nil else{throw ExternalPaymentError.invalidService}
        let result=try await get(payment:nil)
        guard result.status==402,let header=result.paymentRequired else{throw ExternalPaymentError.invalidChallenge}
        return try PaymentRequest.discover(header:header,resource:url.absoluteString,maximumAmount:maximumAmount,now:now)
    }
    fileprivate func submit(_ pending:PendingPayment,now:UInt64) async throws -> Response {
        guard let service,pending.request.service==service else{throw ExternalPaymentError.invalidAuthorization}
        return try await get(payment:pending.header(now:now))
    }
    private func get(payment:String?) async throws -> Response {
        try Task.checkCancellation()
        var request=URLRequest(url:url);request.httpMethod="GET"
        request.setValue("application/json",forHTTPHeaderField:"Accept")
        if let payment{request.setValue(payment,forHTTPHeaderField:"PAYMENT-SIGNATURE")}
        let(bytes,response)=try await session.bytes(for:request)
        defer{bytes.task.cancel()}
        guard let http=response as? HTTPURLResponse,http.url==url,
              !(300...399).contains(http.statusCode),response.expectedContentLength<=65_536
        else{throw ExternalPaymentError.invalidReceipt}
        for field in ["PAYMENT-REQUIRED","PAYMENT-RESPONSE"] {
            guard (http.value(forHTTPHeaderField:field)?.utf8.count ?? 0)<=16_384 else{throw ExternalPaymentError.invalidReceipt}
        }
        var data=Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count<65_536 else{throw ExternalPaymentError.invalidReceipt};data.append(byte)
        }
        return Response(status:http.statusCode,body:data,paymentRequired:http.value(forHTTPHeaderField:"PAYMENT-REQUIRED"),
                        paymentResponse:http.value(forHTTPHeaderField:"PAYMENT-RESPONSE"))
    }
}

actor DevicePaymentJournal:RecoverablePaymentJournal {
    static let shared=DevicePaymentJournal()
    private init(){}
    // Retain the same entry so prior signed payments cannot be bypassed.
    // Access is serialized through this process-wide actor; no app extension
    // or other process may mutate this Keychain item.
    private let key="external-x402-pending-v1"
    private func state() throws -> PaymentJournalState {
        try LocalSecrets.read(PaymentJournalState.self,key:key) ?? PaymentJournalState()
    }
    private func update(_ change:(inout PaymentJournalState) throws -> Void) throws {
        var current=try state();try change(&current)
        try LocalSecrets.write(current,key:key)
    }
    func load() throws -> PendingPayment? {try state().pending()}
    func snapshot() throws -> PaymentJournalState {try state()}
    func expire(_ entry:PaymentJournalState.Entry,evidence:ExpiredPaymentEvidence) throws {
        try update{try $0.expire(entry,evidence:evidence)}
    }
    func complete(_ payment:PendingPayment,completion:PaymentCompletion) throws {
        try update{try $0.complete(payment,completion:completion)}
    }
    func observe(_ payment:PendingPayment,response:PaymentObservation) throws {
        try update{try $0.observe(payment,response:response)}
    }
    func reserve(_ pending:PendingPayment) throws {try update{try $0.reserve(pending)}}
    func beginApproval(_ approval:PaymentApproval) throws {try update{try $0.beginApproval(approval)}}
    func beginSigning(_ approval:PaymentApproval) throws {try update{try $0.beginSigning(approval)}}
    func finishSigning(_ pending:PendingPayment,approval:PaymentApproval) throws {
        try update{try $0.finishSigning(pending,approval:approval)}
    }
    func cancelApproval(_ approval:PaymentApproval) throws {try update{try $0.cancelApproval(approval)}}
}

/// The signature is saved before network transmission. A timeout, cancellation,
/// restart, malformed receipt or expired deadline never clears it or permits a
/// new signature. Only corroborated settlement or expired-unused evidence may
/// archive the original authorization and release the journal.
actor ExternalPaymentRecovery {
    private let journal:any PaymentJournal
    private var busy=false
    init(journal:any PaymentJournal){self.journal=journal}
    func reconcile(using checker:ExternalPaymentReconciliation,claim:PaymentReceipt?,now:UInt64) async throws -> ExternalPaymentReconciliation.Outcome {
        guard !busy else{throw ExternalPaymentError.unresolvedPayment}
        busy=true;defer{busy=false}
        guard let pending=try await journal.load() else{throw ExternalPaymentError.unresolvedPayment}
        return try await checker.reconcile(pending,claim:claim,now:now)
    }
    func submit(_ pending:PendingPayment,through client:ExternalPaymentClient,now:UInt64) async throws -> ExternalPaymentClient.Response {
        guard !busy else{throw ExternalPaymentError.unresolvedPayment}
        busy=true;defer{busy=false}
        try pending.validate(now:now)
        try await journal.reserve(pending)
        try Task.checkCancellation()
        let response=try await client.submit(pending,now:now)
        if let journal=journal as? any RecoverablePaymentJournal {
            let claim=response.paymentResponse.flatMap{try? PaymentReceipt.parse(header:$0,pending:pending,now:now)}
            try await journal.observe(pending,response:PaymentObservation(status:response.status,body:response.body,claim:claim))
        }
        return response
    }
    /// Only independent, finalized-chain reconciliation can release a signed
    /// entry. HTTP success alone never unlocks another purchase.
    func complete(using checker:ExternalPaymentReconciliation,claim:PaymentReceipt?,now:UInt64,
                  response:ExternalPaymentClient.Response? = nil) async throws -> PaymentCompletion? {
        guard !busy,let journal=journal as? any RecoverablePaymentJournal else {
            throw ExternalPaymentError.unresolvedPayment
        }
        busy=true;defer{busy=false}
        guard let pending=try await journal.load() else{throw ExternalPaymentError.unresolvedPayment}
        let saved=try await journal.snapshot()
        let observation=saved.observation
        var locator=claim ?? observation?.claim
        if locator==nil{locator=try await checker.locate(pending,now:now)}
        let outcome=try await checker.reconcile(pending,claim:locator,now:now)
        guard case .confirmed(let evidence)=outcome else{return nil}
        let completion=try PaymentCompletion(payment:pending,transaction:evidence.transaction,
            blockHash:evidence.blockHash,blockNumber:evidence.blockNumber,now:now,
            response:observation?.body ?? response?.body,httpStatus:observation?.status ?? response?.status)
        try await journal.complete(pending,completion:completion)
        return completion
    }
    func releaseExpired(using checker:ExternalPaymentReconciliation) async throws -> Bool {
        guard !busy, let journal=journal as? any RecoverablePaymentJournal else { throw ExternalPaymentError.unresolvedPayment }
        busy=true;defer{busy=false}
        guard let entry=try await journal.snapshot().entry else{return false}
        let request:PaymentRequest, authorization:PaymentAuthorization
        switch entry {
        case .signing(let approval):request=approval.request;authorization=approval.authorization
        case .signed(let pending):request=pending.request;authorization=pending.authorization
        case .approving:return false
        }
        guard let evidence=try await checker.expiredUnused(request:request,authorization:authorization) else{return false}
        try await journal.expire(entry,evidence:evidence)
        return true
    }
}
