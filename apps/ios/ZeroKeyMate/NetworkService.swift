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
struct ProviderList:Decodable,Sendable { let providers:[ServiceProvider]; let indexedBlock:String; let observedAt:String }
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
struct MateIdentity:Codable,Sendable {let name:String;let address:String;let owner:String;let description:String}

actor NetworkService {
    private let configuration:AppConfiguration
    private let session:URLSession
    init(configuration:AppConfiguration) {
        self.configuration=configuration
        let settings=URLSessionConfiguration.ephemeral
        settings.httpCookieStorage=nil;settings.urlCache=nil
        settings.timeoutIntervalForRequest=120;settings.timeoutIntervalForResource=180
        session=URLSession(configuration:settings)
    }
    private func perform<Response:Decodable>(_ path:String,method:String="GET",body:Data?=nil) async throws -> Response {
        guard !configuration.apiToken.isEmpty,let base=URL(string:configuration.apiURL),
              ["https","http"].contains(base.scheme ?? ""),
              let url=URL(string:path,relativeTo:base)?.absoluteURL else {
            throw ProductError.unavailable("外部サービスの接続設定がありません。設定画面で必要な項目を確認してください。")
        }
        var request=URLRequest(url:url)
        request.httpMethod=method;request.httpBody=body
        request.setValue("Bearer \(configuration.apiToken)",forHTTPHeaderField:"Authorization")
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.setValue("no-store",forHTTPHeaderField:"Cache-Control")
        let (data,response)=try await session.data(for:request)
        guard let http=response as? HTTPURLResponse,data.count < 2_000_000 else {throw ProductError.invalidResponse}
        guard (200..<300).contains(http.statusCode) else {
            struct Failure:Decodable {let error:String;let message:String}
            if let failure=try? JSONDecoder().decode(Failure.self,from:data) {throw ProductError.unavailable(failure.message)}
            throw ProductError.unavailable("外部サービスに接続できませんでした（HTTP \(http.statusCode)）。")
        }
        return try JSONDecoder().decode(Response.self,from:data)
    }
    func providers(service:MateService) async throws -> ProviderList {
        try await perform("/v1/providers?service=\(service.rawValue)")
    }
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
    func identity(name:String) async throws -> MateIdentity {
        guard let query=name.addingPercentEncoding(withAllowedCharacters:.urlQueryAllowed) else {throw ProductError.invalidResponse}
        return try await perform("/v1/names/resolve?name=\(query)")
    }
    func claimName(label:String,owner:String,agent:String,signature:String,nonce:String,expiresAt:UInt64) async throws -> MateIdentity {
        struct Request:Encodable {let label:String;let owner:String;let agent:String;let signature:String;let nonce:String;let expiresAt:UInt64}
        return try await perform("/v1/names",method:"POST",body:JSONEncoder().encode(Request(label:label,owner:owner,agent:agent,signature:signature,nonce:nonce,expiresAt:expiresAt)))
    }
}

actor EthereumRPC {
    private let url:URL?
    private let session=URLSession(configuration:.ephemeral)
    init(url:String){self.url=URL(string:url)}
    struct Receipt:Decodable,Sendable {let status:String;let transactionHash:String;let blockHash:String;let blockNumber:String}
    private struct RPCError:Decodable {let code:Int;let message:String}
    private struct Response<T:Decodable>:Decodable {let result:T?;let error:RPCError?}
    private func call<T:Decodable>(method:String,params:[String]) async throws -> T? {
        guard let url,url.scheme == "https" else {throw ProductError.unavailable("Sepolia RPCの設定がありません。")}
        var request=URLRequest(url:url);request.httpMethod="POST";request.timeoutInterval=20
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.httpBody=try JSONSerialization.data(withJSONObject:["jsonrpc":"2.0","id":1,"method":method,"params":params])
        let (data,response)=try await session.data(for:request)
        guard let http=response as? HTTPURLResponse,http.statusCode == 200,data.count < 1_000_000 else {throw ProductError.invalidResponse}
        let decoded=try JSONDecoder().decode(Response<T>.self,from:data)
        guard decoded.error == nil else {throw ProductError.unavailable("Sepolia RPCで操作を確認できませんでした。")}
        return decoded.result
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
                guard receipt.transactionHash.lowercased() == hash.lowercased(),receipt.status == "0x1" else {
                    throw ProductError.unavailable("取引は取り消されました。実行成功として記録していません。")
                }
                return receipt
            }
            try await Task.sleep(for:.seconds(2))
        }
        throw ProductError.unavailable("取引は送信済みですが、まだ確定を確認できません。再送せず、取引履歴を確認してください。")
    }
}
