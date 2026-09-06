import Foundation
import MateCore

struct ServiceProvider: Codable, Identifiable, Equatable, Sendable {
    let id:String
    let name:String
    let service:UInt8
    let price:String
    let recipient:String
    let ensName:String
    let feedback:Int
}
struct ProviderList:Decodable,Sendable {let providers:[ServiceProvider];let indexedBlock:String;let observedAt:String}
struct AccountState:Decodable,Sendable {let nonce:String;let balance:String;let tokenBalance:String;let gasBalance:String}
struct OnchainMandate:Decodable,Sendable {let owner:String;let agent:String;let policyHash:String;let validUntil:UInt64;let spent:String;let revoked:Bool}
struct GrantReceipt:Decodable,Sendable {let mandateId:String;let transactionHash:String;let blockNumber:String}
struct ExecutionReceipt:Codable,Identifiable,Sendable {
    var id:String {actionHash}
    let transactionHash:String
    let blockNumber:String
    let actionHash:String
    let proofHash:String
    let result:String
    let spentAfter:String
}
struct MateIdentity: Codable, Sendable {
    let name: String
    let address: String
    let owner: String
    let description: String
    let resolver: String?
    let node: String?
    let avatar: String?
}
struct APIProblem: Error, LocalizedError, Decodable {
    let error: String
    let message: String
    var errorDescription: String? { message }
}
final class RejectRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

actor NetworkService {
    
    private let configuration:AppConfiguration
    private let session:URLSession
    init(configuration:AppConfiguration) {
        self.configuration=configuration
        let settings=URLSessionConfiguration.ephemeral
        settings.httpCookieStorage=nil;settings.urlCache=nil
        settings.timeoutIntervalForRequest=120;settings.timeoutIntervalForResource=180
        session=URLSession(configuration:settings, delegate:RejectRedirects(), delegateQueue:nil)
    }
    private static func allowsLoopback(_ url: URL) -> Bool {
        #if targetEnvironment(simulator)
        return url.scheme == "http" && ["127.0.0.1", "localhost", "[::1]", "::1"].contains(url.host ?? "")
        #else
        return false
        #endif
    }
    private func perform<Response:Decodable>(_ path:String,method:String="GET",body:Data?=nil) async throws -> Response {
        guard !configuration.apiToken.isEmpty,let base=URL(string:configuration.apiURL),
              (base.scheme == "https" || Self.allowsLoopback(base)),
              base.user == nil, base.password == nil,
              let url=URL(string:path,relativeTo:base)?.absoluteURL,url.host == base.host else {
            throw ProductError.unavailable("外部サービスはHTTPSで接続してください。Simulatorの同一Mac内通信だけはlocalhostを利用できます。")
        }
        var request=URLRequest(url:url)
        request.httpMethod=method;request.httpBody=body
        request.setValue("Bearer \(configuration.apiToken)",forHTTPHeaderField:"Authorization")
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.setValue("no-store",forHTTPHeaderField:"Cache-Control")
        let (stream,response) = try await session.bytes(for: request)
        var data = Data()
        for try await byte in stream {
            guard data.count < 2_000_000 else { throw ProductError.invalidResponse }
            data.append(byte)
        }
        guard let http=response as? HTTPURLResponse else {throw ProductError.invalidResponse}
        guard (200..<300).contains(http.statusCode) else {
            if let failure=try? JSONDecoder().decode(APIProblem.self,from:data) {throw failure}
            throw ProductError.unavailable("外部サービスに接続できませんでした（HTTP \(http.statusCode)）。")
        }
        return try JSONDecoder().decode(Response.self,from:data)
    }
    func providers(service:MateService) async throws -> ProviderList {try await perform("/v1/providers?service=\(service.rawValue)")}
    func account(owner:String) async throws -> AccountState {
        _=try CanonicalBytes.hex(owner,count:20)
        return try await perform("/v1/account?owner=\(owner)")
    }
    func mandate(id:String) async throws -> OnchainMandate {
        _=try CanonicalBytes.hex(id,count:32)
        return try await perform("/v1/state?mandateId=\(id)")
    }
    func register(grant:MandateGrant,signature:String) async throws -> GrantReceipt {
        struct Request:Encodable {let grant:MandateGrant;let signature:String}
        return try await perform("/v1/grants",method:"POST",body:JSONEncoder().encode(Request(grant:grant,signature:signature)))
    }
    func execute(action:MandateAction,signature:String,proof:Data,payload:String,providerID:String) async throws -> ExecutionReceipt {
        struct Request:Encodable {let action:MandateAction;let agentSignature:String;let proof:String;let payload:String;let providerId:String}
        let request=Request(action:action,agentSignature:signature,proof:proof.base64EncodedString(),payload:payload,providerId:providerID)
        return try await perform("/v1/execute",method:"POST",body:JSONEncoder().encode(request))
    }
    func receipt(actionHash:String) async throws -> ExecutionReceipt {
        _=try CanonicalBytes.hex(actionHash,count:32)
        return try await perform("/v1/receipts?actionHash=\(actionHash)")
    }
    func retire(_ action: MandateAction) async throws -> String {
        struct Response: Decodable { let retired: Bool; let actionHash: String }
        let response: Response = try await perform("/v1/retire", method:"POST", body:JSONEncoder().encode(action))
        guard response.retired else { throw ProductError.invalidResponse }
        return response.actionHash
    }
    func identity(name:String) async throws -> MateIdentity {
        var components=URLComponents();components.path="/v1/names/resolve"
        components.queryItems=[URLQueryItem(name:"name",value:name)]
        guard let path=components.string else {throw ProductError.invalidResponse}
        return try await perform(path)
    }
    func claimName(label:String,owner:String,agent:String,signature:String,nonce:String,expiresAt:UInt64) async throws -> MateIdentity {
        struct Request:Encodable {let label:String;let owner:String;let agent:String;let signature:String;let nonce:String;let expiresAt:UInt64}
        return try await perform("/v1/names",method:"POST",body:JSONEncoder().encode(Request(label:label,owner:owner,agent:agent,signature:signature,nonce:nonce,expiresAt:expiresAt)))
    }
}

actor EthereumRPC {
    private let url:URL?
    private let session=URLSession(configuration:.ephemeral, delegate:RejectRedirects(), delegateQueue:nil)
    init(url:String){self.url=URL(string:url)}
    struct Log: Decodable, Sendable { let address:String;let topics:[String];let data:String }
    struct Receipt:Decodable,Sendable {let status:String;let transactionHash:String;let blockHash:String;let blockNumber:String;let logs:[Log]}
    private struct RPCError:Decodable {let code:Int;let message:String}
    private struct Response<T:Decodable>:Decodable {let result:T?;let error:RPCError?}
    private func call<T:Decodable>(method:String,params:[Any]) async throws -> T? {
        guard let url,url.scheme == "https" else {throw ProductError.unavailable("Sepolia RPCの設定がありません。")}
        var request=URLRequest(url:url);request.httpMethod="POST";request.timeoutInterval=20
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.httpBody=try JSONSerialization.data(withJSONObject:["jsonrpc":"2.0","id":1,"method":method,"params":params])
        let (stream,response)=try await session.bytes(for:request)
        var data=Data()
        for try await byte in stream {
            guard data.count < 1_000_000 else { throw ProductError.invalidResponse }; data.append(byte)
        }
        guard let http=response as? HTTPURLResponse,http.statusCode == 200 else {throw ProductError.invalidResponse}
        let decoded=try JSONDecoder().decode(Response<T>.self,from:data)
        guard decoded.error == nil else {throw ProductError.unavailable("Sepolia RPCで操作を確認できませんでした。")}
        return decoded.result
    }
    struct TransactionParameters: Sendable { let nonce: String; let gas: String; let gasPrice: String }
    private func quantity(_ value: String?) throws -> UInt64 {
        guard let value, value.hasPrefix("0x"), let number=UInt64(value.dropFirst(2),radix:16) else { throw ProductError.invalidResponse }
        return number
    }
    func prepareCall(from: String, to: String, data: String) async throws -> TransactionParameters {
        try await ensureSepolia()
        _=try CanonicalBytes.hex(from,count:20); _=try CanonicalBytes.hex(to,count:20)
        let nonce: String?=try await call(method:"eth_getTransactionCount",params:[from,"pending"])
        let gasPrice: String?=try await call(method:"eth_gasPrice",params:[])
        let estimate: String?=try await call(method:"eth_estimateGas",params:[["from":from,"to":to,"data":data,"value":"0x0"]])
        let nonceValue=try quantity(nonce), gasPriceValue=try quantity(gasPrice), estimateValue=try quantity(estimate)
        guard gasPriceValue>0,gasPriceValue<=1_000_000_000_000,estimateValue>0,estimateValue<=1_600_000 else {
            throw ProductError.unavailable("予想ガス費用または実行量が安全上限を超えています。署名していません。")
        }
        return TransactionParameters(nonce:"0x"+String(nonceValue,radix:16),
            gas:"0x"+String(estimateValue*120/100,radix:16),gasPrice:"0x"+String(gasPriceValue,radix:16))
    }
    func broadcast(_ operation: SignedWalletOperation) async throws -> Receipt {
        try await ensureSepolia()
        let bytes=try CanonicalBytes.hex(operation.raw,count:(operation.raw.utf8.count-2)/2)
        guard CanonicalBytes.hexString(EthereumKeccak.digest(bytes))==operation.hash else { throw ProductError.invalidResponse }
        // Persisted signed bytes are replay-safe. A lost response never causes a new signature or nonce.
        do {
            let result: String?=try await call(method:"eth_sendRawTransaction",params:[operation.raw])
            guard result?.lowercased()==operation.hash else { throw ProductError.invalidResponse }
        } catch {
            // The node may report "already known". Only a receipt can establish success.
        }
        return try await confirm(hash:operation.hash)
    }
    private func ethCall(address: String, data: String) async throws -> String {
        _=try CanonicalBytes.hex(address,count:20)
        guard let value: String=try await call(method:"eth_call",params:[["to":address,"data":data],"latest"]) else {
            throw ProductError.invalidResponse
        }
        return value
    }
    func identity(name: String) async throws -> MateIdentity {
        try await ensureSepolia()
        let labels=try EthereumABI.labels(name)
        guard labels.last=="eth" else { throw ProductError.invalidResponse }
        // ENSv2 Sepolia deployment pinned in config/ens-sepolia.json, not an ENSv1 registry.
        var registry="0x11b5bfbe9078d826b1edbdd1cfc12f5828d9f50c"
        for label in labels.reversed().dropLast() {
            registry=try EthereumABI.decodeAddress(await ethCall(address:registry,
                data:EthereumABI.call("getSubregistry(string)",[.dynamic(Data(label.utf8))])))
            guard registry != "0x"+String(repeating:"00",count:20) else { throw ProductError.unavailable("ENSv2で名前を解決できません。") }
        }
        let label=try EthereumABI.labels(name)[0]
        let owner=try EthereumABI.decodeAddress(await ethCall(address:registry,
            data:EthereumABI.call("findOwner(string)",[.dynamic(Data(label.utf8))])))
        let resolver=try EthereumABI.decodeAddress(await ethCall(address:registry,
            data:EthereumABI.call("getResolver(string)",[.dynamic(Data(label.utf8))])))
        guard owner != "0x"+String(repeating:"00",count:20), resolver != "0x"+String(repeating:"00",count:20) else {
            throw ProductError.unavailable("名前は未登録か期限切れです。")
        }
        let node=try EthereumABI.namehash(name)
        let account=try EthereumABI.decodeAddress(await ethCall(address:resolver,data:EthereumABI.call("addr(bytes32)",[.word(node)])))
        let description=try EthereumABI.decodeText(await ethCall(address:resolver,data:EthereumABI.call("text(bytes32,string)",[.word(node),.dynamic(Data("agent-context".utf8))])))
        let avatar=try EthereumABI.decodeText(await ethCall(address:resolver,data:EthereumABI.call("text(bytes32,string)",[.word(node),.dynamic(Data("avatar".utf8))])))
        return MateIdentity(name:name,address:account,owner:owner,description:description,resolver:resolver,
            node:CanonicalBytes.hexString(node),avatar:avatar)
    }
    func confirmGrant(transactionHash: String, grant: MandateGrant, vault: String) async throws {
        let receipt=try await confirm(hash:transactionHash)
        let id=try MandateDigest.grant(grant,chainID:11_155_111,vault:vault)
        let topic=CanonicalBytes.hexString(EthereumKeccak.digest(Data("Granted(bytes32,address,address,bytes32,uint64)".utf8)))
        let owner=CanonicalBytes.hexString(try EthereumABI.addressWord(grant.owner))
        let agent=CanonicalBytes.hexString(try EthereumABI.addressWord(grant.agent))
        guard let log=receipt.logs.first(where:{$0.address.lowercased()==vault.lowercased() && $0.topics.map{$0.lowercased()}==[topic,id,owner,agent]}) else {
            throw ProductError.invalidResponse
        }
        let data=try CanonicalBytes.hex(log.data,count:64)
        guard CanonicalBytes.hexString(Data(data.prefix(32)))==grant.policyHash.lowercased(),
              try EthereumABI.unsignedWord(Data(data.suffix(32)))==grant.validUntil else { throw ProductError.invalidResponse }
    }
    func confirmExecution(_ receipt: ExecutionReceipt, action: MandateAction, vault: String) async throws {
        let mined=try await confirm(hash:receipt.transactionHash)
        let digest=LocalSecrets.hash(try action.material(chainID:11_155_111,vault:vault))
        let topic=CanonicalBytes.hexString(EthereumKeccak.digest(Data("Executed(bytes32,bytes32,bytes32,address,uint64,uint8,bytes32,uint64)".utf8)))
        guard let log=mined.logs.first(where:{$0.address.lowercased()==vault.lowercased() && $0.topics.map{$0.lowercased()}==[topic,action.mandateId.lowercased(),digest,action.nonce.lowercased()]}) else {
            throw ProductError.invalidResponse
        }
        let data=try CanonicalBytes.hex(log.data,count:160)
        let recipient=try EthereumABI.decodeAddress(CanonicalBytes.hexString(data.subdata(in:0..<32)))
        let amount=try EthereumABI.unsignedWord(data.subdata(in:32..<64))
        let service=try EthereumABI.unsignedWord(data.subdata(in:64..<96))
        let spentAfter=try EthereumABI.unsignedWord(data.subdata(in:128..<160))
        guard let before=UInt64(action.spentBefore),before<=UInt64.max-amount,
              recipient.lowercased()==action.recipient.lowercased(),String(amount)==action.amount,
              service==UInt64(action.service),spentAfter==before+amount,String(spentAfter)==receipt.spentAfter,
              CanonicalBytes.hexString(data.subdata(in:96..<128))==receipt.proofHash.lowercased() else { throw ProductError.invalidResponse }
    }
    func confirmGrantExpired(validUntil: UInt64) async throws {
        try await ensureSepolia()
        struct Block: Decodable {let timestamp:String}
        guard let block: Block=try await call(method:"eth_getBlockByNumber",params:["finalized",false]),
              try quantity(block.timestamp)>=validUntil else { throw ProductError.unavailable("署名済みの承認はまだ有効です。期限切れが確定するまで保持してください。") }
    }
    func confirmExpiredAndUnused(_ action: MandateAction, vault: String) async throws {
        try await ensureSepolia()
        struct Block: Decodable {let number:String;let timestamp:String}
        guard let block: Block=try await call(method:"eth_getBlockByNumber",params:["finalized",false]),
              try quantity(block.timestamp)>=action.expiresAt else { throw ProductError.unavailable("まだ期限切れがチェーン上で確定していません。") }
        let data=try EthereumABI.call("usedNonces(bytes32,bytes32)",[
            .word(CanonicalBytes.hex(action.mandateId,count:32)),.word(CanonicalBytes.hex(action.nonce,count:32))])
        let encoded: String?=try await call(method:"eth_call",params:[["to":vault,"data":data],block.number])
        guard let encoded,try CanonicalBytes.hex(encoded,count:32)==EthereumABI.word(0) else {
            throw ProductError.unavailable("この依頼には使用済みの記録があります。削除せず、結果を復旧してください。")
        }
    }
    func ensureSepolia() async throws {
        let chain:String?=try await call(method:"eth_chainId",params:[])
        guard chain?.lowercased() == "0xaa36a7" else {throw ProductError.unavailable("接続先はSepoliaではありません。署名・送金を停止しました。")}
    }
    func confirm(hash:String) async throws -> Receipt {
        _=try CanonicalBytes.hex(hash,count:32)
        try await ensureSepolia()
        for _ in 0..<60 {
            try Task.checkCancellation()
            if let receipt:Receipt=try await call(method:"eth_getTransactionReceipt",params:[hash]) {
                guard receipt.transactionHash.lowercased() == hash.lowercased(),["0x0","0x1"].contains(receipt.status) else {
                    throw ProductError.unavailable("取引は取り消されました。実行成功として記録していません。")
                }
                guard let block = UInt64(receipt.blockNumber.dropFirst(2), radix: 16) else { throw ProductError.invalidResponse }
                let current: String? = try await call(method: "eth_blockNumber", params: [])
                if let current, let height = UInt64(current.dropFirst(2), radix: 16), height > block,
                   let again: Receipt = try await call(method: "eth_getTransactionReceipt", params: [hash]),
                   again.blockHash == receipt.blockHash, again.status == receipt.status {
                    if again.status == "0x0" { throw ProductError.transactionReverted(hash) }
                    return again
                }
            }
            try await Task.sleep(for:.seconds(2))
        }
        throw ProductError.unavailable("取引は送信済みですが、まだ確定を確認できません。再送せず、取引履歴を確認してください。")
    }
}
