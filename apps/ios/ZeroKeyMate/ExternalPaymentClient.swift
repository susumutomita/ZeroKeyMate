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
    private let service:PaymentService
    private let url:URL
    private let session:URLSession
    init(service:PaymentService,configuration:URLSessionConfiguration = .ephemeral) throws {
        url=try service.validate();self.service=service
        configuration.httpShouldSetCookies=false;configuration.httpCookieStorage=nil
        configuration.urlCredentialStorage=nil;configuration.urlCache=nil
        configuration.httpAdditionalHeaders=[:];configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest=30;configuration.timeoutIntervalForResource=45
        session=URLSession(configuration:configuration,delegate:ExternalPaymentRedirects(),delegateQueue:nil)
    }
    deinit{session.invalidateAndCancel()}
    func quote(now:UInt64) async throws -> PaymentRequest {
        let result=try await get(payment:nil)
        guard result.status==402,let header=result.paymentRequired else{throw ExternalPaymentError.invalidChallenge}
        return try PaymentRequest.parse(header:header,service:service,now:now)
    }
    fileprivate func submit(_ pending:PendingPayment,now:UInt64) async throws -> Response {
        guard pending.request.service==service else{throw ExternalPaymentError.invalidAuthorization}
        return try await get(payment:pending.header(now:now))
    }
    private func get(payment:String?) async throws -> Response {
        try Task.checkCancellation()
        var request=URLRequest(url:url);request.httpMethod="GET"
        request.setValue("application/json",forHTTPHeaderField:"Accept")
        if let payment{request.setValue(payment,forHTTPHeaderField:"PAYMENT-SIGNATURE")}
        let(bytes,response)=try await session.bytes(for:request)
        defer{bytes.task.cancel()}
        guard let http=response as? HTTPURLResponse,http.url?.absoluteString==service.resource,
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

protocol PaymentJournal:Sendable {
    func load() async throws -> PendingPayment?
    /// Atomically retain this payment, reject a different unresolved payment,
    /// or permit exactly the same saved signature to be retried.
    func reserve(_ pending:PendingPayment) async throws
}

actor DevicePaymentJournal:PaymentJournal {
    static let shared=DevicePaymentJournal()
    private init(){}
    // A single unresolved external payment deliberately blocks every new one.
    // Do not reuse the dedicated shop's pending-order Keychain entry.
    private let key="external-x402-pending-v1"
    func load() throws -> PendingPayment? {try LocalSecrets.read(PendingPayment.self,key:key)}
    func reserve(_ pending:PendingPayment) throws {
        if let saved=try load() {
            guard saved==pending else{throw ExternalPaymentError.unresolvedPayment}
        }else{try LocalSecrets.write(pending,key:key)}
    }
}

/// The signature is saved before network transmission. A timeout, cancellation,
/// restart, malformed receipt or expired deadline never clears it or permits a
/// new signature. Reconciliation only returns evidence; the journal stays locked.
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
        return try await client.submit(pending,now:now)
    }
}
