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
    enum Funds:Equatable,Sendable {case sufficient,insufficient,unavailable}
    private let primary:PaymentReadRPC
    private let secondary:PaymentReadRPC

    // Neither merchant responses nor model output can select the RPC endpoints.
    init(configuration:URLSessionConfiguration = .ephemeral) {
        primary=PaymentReadRPC(url:URL(string:"https://rpc.testnet.arc.io")!,configuration:configuration)
        secondary=PaymentReadRPC(url:URL(string:"https://rpc.drpc.testnet.arc.io")!,configuration:configuration)
    }
    func funds(payer:String,amount:UInt64) async throws -> Funds {
        guard amount>0,amount<=500_000 else{throw ExternalPaymentError.invalidAuthorization}
        _ = try CanonicalBytes.hex(payer,count:20)
        do {
            try await primary.checkChain();try await secondary.checkChain()
            let first=try await primary.block("finalized"),second=try await secondary.block("finalized")
            let height=min(try first.height(),try second.height()),tag="0x"+String(height,radix:16)
            let block=try await primary.block(tag),other=try await secondary.block(tag)
            guard block==other,try block.height()==height else{return .unavailable}
            if try first.height()==height,first != block{return .unavailable}
            if try second.height()==height,second != block{return .unavailable}
            let balance=try await primary.balance(payer,blockHash:block.hash)
            let otherBalance=try await secondary.balance(payer,blockHash:block.hash)
            guard balance==otherBalance else{return .unavailable}
            let minimum=Data(repeating:0,count:24)+CanonicalBytes.u64(amount)
            return balance.lexicographicallyPrecedes(minimum) ? .insufficient:.sufficient
        } catch {
            try Task.checkCancellation();return .unavailable
        }
    }

    /// Search recent token events for a missing HTTP receipt. This only finds a
    /// locator: reconcile still verifies the canonical receipt and transfer.
    /// Older payments remain recoverable by entering their transaction hash.
    func locate(_ pending:PendingPayment,now:UInt64) async throws -> PaymentReceipt? {
        try pending.validate(now:now,allowExpired:true)
        do {
            try await primary.checkChain();try await secondary.checkChain()
            let head=try await primary.block("finalized")
            let height=try head.height()
            let hashes=try await primary.authorizationTransactions(pending.authorization,from:height > 999 ? height-999:0,to:height)
            guard hashes.count==1,let hash=hashes.first else{return nil}
            return try PaymentReceipt.unverifiedLocator(hash,pending:pending,now:now)
        } catch {
            try Task.checkCancellation()
            return nil
        }
    }

    /// Both fixed RPCs must show the nonce unused in the same finalized block
    /// after the token's validBefore deadline. Unknown/reverted RPC is not false.
    func expiredUnused(request:PaymentRequest,authorization:PaymentAuthorization) async throws -> ExpiredPaymentEvidence? {
        try authorization.validate(request:request)
        do {
            try Task.checkCancellation()
            try await primary.checkChain();try await secondary.checkChain()
            let first=try await primary.block("finalized"),second=try await secondary.block("finalized")
            let height=min(try first.height(),try second.height()),tag="0x"+String(height,radix:16)
            let checkpoint=try await primary.block(tag),other=try await secondary.block(tag)
            guard checkpoint==other,try checkpoint.height()==height,
                  let end=UInt64(authorization.validBefore),try checkpoint.time()>=end else{return nil}
            if try first.height()==height,first != checkpoint{return nil}
            if try second.height()==height,second != checkpoint{return nil}
            guard try await primary.authorizationUnused(authorization,blockHash:checkpoint.hash),
                  try await secondary.authorizationUnused(authorization,blockHash:checkpoint.hash) else{return nil}
            let after=try await primary.block(tag),otherAfter=try await secondary.block(tag)
            guard after==checkpoint,otherAfter==checkpoint else{return nil}
            let finalFirst=try await primary.block("finalized"),finalSecond=try await secondary.block("finalized")
            let h1=try first.height(),h2=try second.height(),f1=try finalFirst.height(),f2=try finalSecond.height()
            guard f1>=h1,f2>=h2,
                  f1 != h1 || finalFirst==first,f2 != h2 || finalSecond==second,
                  f1 != f2 || finalFirst==finalSecond else{return nil}
            try Task.checkCancellation()
            return try ExpiredPaymentEvidence(authorization:authorization,blockHash:checkpoint.hash,
                blockNumber:height,timestamp:checkpoint.time())
        } catch {
            try Task.checkCancellation()
            return nil
        }
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
            // Bind the numeric reread to the block actually advertised as finalized.
            // Agreement on a replacement block must not erase that contradiction.
            if try firstHead.height()==height,firstHead != checkpoint{return .unresolved}
            if try secondHead.height()==height,secondHead != checkpoint{return .unresolved}

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
            let finalFirstHead=try await primary.block("finalized")
            let finalSecondHead=try await secondary.block("finalized")
            let finalFirstHeight=try finalFirstHead.height(),finalSecondHeight=try finalSecondHead.height()
            let firstHeight=try firstHead.height(),secondHeight=try secondHead.height()
            guard finalFirstHeight>=firstHeight,finalSecondHeight>=secondHeight,
                  finalFirstHeight != firstHeight || finalFirstHead==firstHead,
                  finalSecondHeight != secondHeight || finalSecondHead==secondHead,
                  finalFirstHeight != finalSecondHeight || finalFirstHead==finalSecondHead
            else{return .unresolved}
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
    func balance(_ payer:String,blockHash:String) async throws -> Data {
        let address=try CanonicalBytes.hexString(Data(repeating:0,count:12)+CanonicalBytes.hex(payer,count:20))
        let result:String?=try await call("eth_call",[["to":AgeShopProtocol.token,"data":"0x70a08231"+address.dropFirst(2)],
            ["blockHash":blockHash,"requireCanonical":true]])
        guard let result else{throw ExternalPaymentError.invalidReceipt}
        return try CanonicalBytes.hex(result,count:32)
    }
    func authorizationUnused(_ authorization:PaymentAuthorization,blockHash:String) async throws -> Bool {
        let from=try CanonicalBytes.hex(authorization.from,count:20)
        let nonce=try CanonicalBytes.hex(authorization.nonce,count:32)
        // authorizationState(address,bytes32); EIP-1898 prevents number/hash races.
        let data="0xe94a0102" + String(CanonicalBytes.hexString(Data(repeating:0,count:12)+from+nonce).dropFirst(2))
        let result:String?=try await call("eth_call",[["to":AgeShopProtocol.token,"data":data],
            ["blockHash":blockHash,"requireCanonical":true]])
        return result == "0x"+String(repeating:"0",count:64)
    }
    func authorizationTransactions(_ authorization:PaymentAuthorization,from:UInt64,to:UInt64) async throws -> Set<String> {
        let payer=try CanonicalBytes.hexString(Data(repeating:0,count:12)+CanonicalBytes.hex(authorization.from,count:20))
        let topics=["0x98de503528ee59b575ef0c0a2576a82497bfc029a5685b209e9ec333479b10a5",payer,authorization.nonce.lowercased()]
        let logs:[Log]?=try await call("eth_getLogs",[["address":AgeShopProtocol.token,"topics":topics,
            "fromBlock":"0x"+String(from,radix:16),"toBlock":"0x"+String(to,radix:16)]])
        guard let logs,logs.count<=1 else{throw ExternalPaymentError.invalidReceipt}
        for log in logs {
            guard !log.removed,log.address.lowercased()==AgeShopProtocol.token,log.topics.map({$0.lowercased()})==topics,
                  log.data=="0x",try Self.quantity(log.blockNumber)>=from,try Self.quantity(log.blockNumber)<=to else{
                throw ExternalPaymentError.invalidReceipt
            }
            try Self.hash(log.transactionHash)
        }
        return Set(logs.map{$0.transactionHash.lowercased()})
    }
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
