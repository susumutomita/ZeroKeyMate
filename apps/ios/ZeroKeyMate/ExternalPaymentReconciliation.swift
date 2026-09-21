import Foundation
import MateCore

private final class PaymentRPCNoRedirects:NSObject,URLSessionTaskDelegate,@unchecked Sendable {
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,
                    newRequest request:URLRequest,completionHandler:@escaping(URLRequest?)->Void){completionHandler(nil)}
}

/// Corroborated RPC evidence, not a cryptographic receipt proof, delivery receipt,
/// or permission to clear the journal. The fixed endpoints may share operators.
actor ExternalPaymentReconciliation {
    struct Evidence:Equatable,Sendable {
        let transaction:String,blockHash:String,checkpointHash:String
        let blockNumber:UInt64,checkpointNumber:UInt64
    }
    enum Outcome:Equatable,Sendable {case unresolved,confirmed(Evidence)}
    private let primary:PaymentReadRPC
    private let secondary:PaymentReadRPC

    // Neither merchant responses nor model output can select the RPC endpoints.
    init(configuration:URLSessionConfiguration = .ephemeral) {
        primary=PaymentReadRPC(url:URL(string:"https://rpc.testnet.arc.io")!,configuration:configuration)
        secondary=PaymentReadRPC(url:URL(string:"https://rpc.drpc.testnet.arc.io")!,configuration:configuration)
    }

    func reconcile(_ pending:PendingPayment,claim:PaymentReceipt?,now:UInt64) async throws -> Outcome {
        try Task.checkCancellation()
        try pending.validate(now:now,allowExpired:true)
        guard let claim else{return .unresolved}
        do {
            try claim.validate(pending:pending,now:now)
            let hash=claim.transaction.lowercased()
            try await primary.checkChain()
            try await secondary.checkChain()
            let firstHead=try await primary.block("finalized")
            let secondHead=try await secondary.block("finalized")
            let height=min(try firstHead.height(),try secondHead.height())
            let tag="0x"+String(height,radix:16)
            let checkpoint=try await primary.block(tag)
            let otherCheckpoint=try await secondary.block(tag)
            guard checkpoint==otherCheckpoint,try checkpoint.height()==height else{return .unresolved}

            guard let receipt=try await primary.receipt(hash),
                  let otherReceipt=try await secondary.receipt(hash),receipt==otherReceipt,
                  receipt.transactionHash.lowercased()==hash,receipt.status=="0x1",
                  try PaymentReadRPC.quantity(receipt.blockNumber)<=height else{return .unresolved}
            let block=try await primary.block(receipt.blockNumber)
            let otherBlock=try await secondary.block(receipt.blockNumber)
            guard block==otherBlock,block.number==receipt.blockNumber,
                  block.hash.lowercased()==receipt.blockHash.lowercased(),
                  try block.time()<=checkpoint.time(),
                  let index=Int(exactly:try PaymentReadRPC.quantity(receipt.transactionIndex)),
                  index<block.transactions.count,block.transactions[index].lowercased()==hash,
                  let end=UInt64(pending.authorization.validBefore),
                  try block.time()>0,try block.time()<end else{return .unresolved}
            try receipt.validateLogs()
            try claim.validateTransfer(pending:pending,logs:receipt.logs.map{
                AgeShopReceipt.Log(address:$0.address,topics:$0.topics,data:$0.data)
            },now:now)
            // A consistent finalized checkpoint cannot change while reading it.
            // If it does, fail closed instead of treating an elapsed deadline as unpaid.
            let finalPrimary=try await primary.block(tag)
            let finalSecondary=try await secondary.block(tag)
            guard finalPrimary==checkpoint,finalSecondary==checkpoint else{return .unresolved}
            try Task.checkCancellation()
            return .confirmed(Evidence(transaction:hash,blockHash:block.hash.lowercased(),
                checkpointHash:checkpoint.hash.lowercased(),blockNumber:try block.height(),checkpointNumber:height))
        }catch {
            try Task.checkCancellation()
            if error is CancellationError{throw error}
            // Null, malformed, reverted, unavailable or contradictory is unknown,
            // never "not paid". No signature or journal mutation is possible here.
            return .unresolved
        }
    }
}

private actor PaymentReadRPC {
    struct Block:Decodable,Equatable,Sendable {
        let hash:String,number:String,timestamp:String,transactions:[String]
        func height() throws -> UInt64{try PaymentReadRPC.quantity(number)}
        func time() throws -> UInt64{try PaymentReadRPC.quantity(timestamp)}
        func validate() throws {
            try PaymentReadRPC.hash(hash);_ = try height();_ = try time()
            guard transactions.count<=8192 else{throw ExternalPaymentError.invalidReceipt}
            for transaction in transactions{try PaymentReadRPC.hash(transaction)}
        }
    }
    struct Log:Decodable,Equatable,Sendable {
        let address:String,topics:[String],data:String
        let transactionHash:String,blockHash:String,blockNumber:String,transactionIndex:String,logIndex:String
        let removed:Bool
    }
    struct Receipt:Decodable,Equatable,Sendable {
        let transactionHash:String,blockHash:String,blockNumber:String,transactionIndex:String,status:String
        let logs:[Log]
        func validateLogs() throws {
            try PaymentReadRPC.hash(transactionHash);try PaymentReadRPC.hash(blockHash)
            _ = try PaymentReadRPC.quantity(blockNumber);_ = try PaymentReadRPC.quantity(transactionIndex)
            guard (1...256).contains(logs.count) else{throw ExternalPaymentError.invalidReceipt}
            var previous:UInt64?
            for log in logs {
                let index=try PaymentReadRPC.quantity(log.logIndex)
                guard !log.removed,log.transactionHash.lowercased()==transactionHash.lowercased(),
                      log.blockHash.lowercased()==blockHash.lowercased(),log.blockNumber==blockNumber,
                      log.transactionIndex==transactionIndex,previous==nil || index>previous!,
                      log.topics.count<=4,log.data.utf8.count<=65_538 else{throw ExternalPaymentError.invalidReceipt}
                _ = try CanonicalBytes.hex(log.address,count:20)
                for topic in log.topics{_ = try CanonicalBytes.hex(topic,count:32)}
                guard log.data.hasPrefix("0x"),log.data.count%2==0,
                      log.data.dropFirst(2).allSatisfy({$0.isASCII && $0.isHexDigit})
                else{throw ExternalPaymentError.invalidReceipt}
                previous=index
            }
        }
    }
    private struct Envelope<T:Decodable>:Decodable {
        let jsonrpc:String,id:Int,result:T?
        private enum CodingKeys:String,CodingKey{case jsonrpc,id,result,error}
        init(from decoder:Decoder) throws {
            let c=try decoder.container(keyedBy:CodingKeys.self)
            guard !c.contains(.error) else{throw ExternalPaymentError.invalidReceipt}
            jsonrpc=try c.decode(String.self,forKey:.jsonrpc);id=try c.decode(Int.self,forKey:.id)
            result=try c.decodeIfPresent(T.self,forKey:.result)
        }
    }
    private let url:URL,session:URLSession
    init(url:URL,configuration:URLSessionConfiguration) {
        self.url=url
        let config=configuration.copy() as! URLSessionConfiguration
        config.httpCookieStorage=nil;config.httpShouldSetCookies=false;config.urlCredentialStorage=nil
        config.urlCache=nil;config.httpAdditionalHeaders=[:];config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest=15;config.timeoutIntervalForResource=20
        session=URLSession(configuration:config,delegate:PaymentRPCNoRedirects(),delegateQueue:nil)
    }
    deinit{session.invalidateAndCancel()}
    static func quantity(_ value:String) throws -> UInt64 {
        guard value.hasPrefix("0x"),let number=UInt64(value.dropFirst(2),radix:16),
              value=="0x"+String(number,radix:16) else{throw ExternalPaymentError.invalidReceipt}
        return number
    }
    static func hash(_ value:String) throws {
        guard try CanonicalBytes.hex(value,count:32).contains(where:{$0 != 0}) else{throw ExternalPaymentError.invalidReceipt}
    }
    func checkChain() async throws {
        let value:String?=try await call("eth_chainId",[])
        guard let value,try Self.quantity(value)==AgeShopProtocol.chainID else{throw ExternalPaymentError.invalidReceipt}
    }
    func block(_ tag:String) async throws -> Block {
        let block:Block?=try await call("eth_getBlockByNumber",[tag,false])
        guard let block else{throw ExternalPaymentError.invalidReceipt}
        try block.validate();return block
    }
    func receipt(_ hash:String) async throws -> Receipt?{try await call("eth_getTransactionReceipt",[hash])}
    private func call<T:Decodable>(_ method:String,_ params:[Any]) async throws -> T? {
        try Task.checkCancellation()
        var request=URLRequest(url:url);request.httpMethod="POST"
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.httpBody=try JSONSerialization.data(withJSONObject:["jsonrpc":"2.0","id":1,"method":method,"params":params])
        let(bytes,response)=try await session.bytes(for:request)
        defer{bytes.task.cancel()}
        guard let http=response as? HTTPURLResponse,http.statusCode==200,http.url==url,
              response.expectedContentLength<=1_048_576 else{throw ExternalPaymentError.invalidReceipt}
        var body=Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard body.count<1_048_576 else{throw ExternalPaymentError.invalidReceipt};body.append(byte)
        }
        let reply=try JSONDecoder().decode(Envelope<T>.self,from:body)
        guard reply.jsonrpc=="2.0",reply.id==1 else{throw ExternalPaymentError.invalidReceipt}
        return reply.result
    }
}
