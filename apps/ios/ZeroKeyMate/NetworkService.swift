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
struct MateIdentity:Codable,Sendable {let name:String;let address:String;let owner:String;let description:String}
struct ExecutionSubmission:Codable,Sendable {
    let action:MandateAction
    let agentSignature:String
    let proof:String
    let payload:String
    let providerId:String
}
struct NetworkFailure:Error,LocalizedError {
    let code:String
    let message:String
    var errorDescription:String? {
        switch code {
        case "configuration_required","invalid_configuration","pairing_required": return "The execution service is not configured. Check the connection settings."
        case "graph_unconfigured","graph_response": return "Provider discovery is unavailable. Check the service's Graph connection."
        case "provider_changed": return "The provider, recipient or price changed. Review a fresh quote."
        case "proof_rejected": return "The proof does not match this request. No new payment was authorized."
        case "owner_signature","agent_signature","attestor_signature": return "The required signature could not be verified."
        case "stale_mandate","mandate_not_found": return "The mandate is missing, expired or its spending state changed. Refresh your rules."
        case "execution_cancelled": return "This execution was cancelled. Review a new request to continue."
        case "circle_unavailable","circle_wallet": return "The Circle proof attestor is unavailable. Check its testnet login and configured wallet."
        default:
            if message.unicodeScalars.allSatisfy({$0.value<128}){return message}
            return "The execution service could not complete this request. Check Activity before retrying a payment."
        }
    }
}
private final class NoRedirects:NSObject,URLSessionTaskDelegate,Sendable {
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,
                    newRequest request:URLRequest,completionHandler:@escaping (URLRequest?)->Void) {
        completionHandler(nil)
    }
}

actor NetworkService {
    private struct Failure:Decodable {let error:String;let message:String}
    private let configuration:AppConfiguration
    private let session:URLSession
    init(configuration:AppConfiguration,sessionConfiguration:URLSessionConfiguration = .ephemeral) {
        self.configuration=configuration
        let settings=sessionConfiguration
        settings.httpCookieStorage=nil;settings.urlCache=nil
        settings.timeoutIntervalForRequest=120;settings.timeoutIntervalForResource=180
        session=URLSession(configuration:settings,delegate:NoRedirects(),delegateQueue:nil)
    }
    private func perform<Response:Decodable>(_ path:String,method:String="GET",body:Data?=nil,authenticated:Bool=true) async throws -> Response {
        guard !authenticated || configuration.pairingValid else {
            throw ProductError.unavailable("Pairing expired. Create a new code on your Mac and renew in Connection settings. Pending requests are preserved.")
        }
        guard let base=URL(string:configuration.apiURL),
              base.user == nil,base.password == nil,base.query == nil,base.fragment == nil,
              ["","/"].contains(base.path),
              base.scheme == "https" || (base.scheme == "http" && ["127.0.0.1","localhost","::1","[::1]"].contains(base.host ?? "")),
              let url=URL(string:path,relativeTo:base)?.absoluteURL,url.host == base.host else {
            throw ProductError.unavailable("Use HTTPS for external services. Localhost is allowed only for Simulator connections to this Mac.")
        }
        var request=URLRequest(url:url)
        request.httpMethod=method;request.httpBody=body
        if authenticated {request.setValue("Bearer \(configuration.apiToken)",forHTTPHeaderField:"Authorization")}
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.setValue("no-store",forHTTPHeaderField:"Cache-Control")
        let (data,response)=try await session.data(for:request)
        guard let http=response as? HTTPURLResponse,data.count < 2_000_000 else {throw ProductError.invalidResponse}
        guard (200..<300).contains(http.statusCode) else {
            if let failure=try? JSONDecoder().decode(Failure.self,from:data) {throw NetworkFailure(code:failure.error,message:failure.message)}
            throw ProductError.unavailable(L10n.format("Could not connect to the external service (HTTP %lld).",http.statusCode))
        }
        return try JSONDecoder().decode(Response.self,from:data)
    }
    func validateDeployment() async throws {
        struct Deployment:Decodable {let chainId:UInt64;let vault:String;let token:String;let actionVersion:String}
        let value:Deployment=try await perform("/v1/configuration",authenticated:false)
        guard value.chainId==configuration.chainID, value.vault.lowercased()==configuration.vault.lowercased(),
              value.token.lowercased()==configuration.token.lowercased(),value.actionVersion=="ZKM-ACT1" else {
            throw ProductError.unavailable("The execution service uses a different network or vault. These settings have not been saved.")
        }
    }
    func pair(code:String) async throws -> AppConfiguration {
        struct Request:Encodable {let code:String}
        struct Response:Decodable {let token:String;let expiresAt:UInt64;let remainingRequests:Int}
        let value:Response=try await perform("/v1/pair",method:"POST",body:JSONEncoder().encode(Request(code:code)),authenticated:false)
        let now=UInt64(Date().timeIntervalSince1970)
        guard value.token.range(of:"^session_[a-f0-9]{64}$",options:.regularExpression) != nil,
              value.expiresAt>now,value.expiresAt<=now+3600,value.remainingRequests>0,value.remainingRequests<=500 else {throw ProductError.invalidResponse}
        var result=configuration;result.apiToken=value.token;result.apiTokenExpiresAt=value.expiresAt
        return result
    }
    func validatePairing() async throws {
        struct Response:Decodable {let paired:Bool}
        let value:Response=try await perform("/v1/session")
        guard value.paired else{throw ProductError.invalidResponse}
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
        let request=ExecutionSubmission(action:action,agentSignature:signature,proof:proof.base64EncodedString(),payload:payload,providerId:providerID)
        return try await submit(request)
    }
    func submit(_ request:ExecutionSubmission) async throws -> ExecutionReceipt {
        return try await perform("/v1/execute",method:"POST",body:JSONEncoder().encode(request))
    }
    func cancel(actionHash:String) async throws {
        struct Request:Encodable{let actionHash:String}
        struct Response:Decodable{let actionHash:String;let status:String}
        _=try CanonicalBytes.hex(actionHash,count:32)
        let result:Response=try await perform("/v1/executions/cancel",method:"POST",body:JSONEncoder().encode(Request(actionHash:actionHash)))
        guard result.actionHash.lowercased()==actionHash.lowercased(),result.status=="cancelled" else{throw ProductError.invalidResponse}
    }
    func receipt(actionHash:String) async throws -> ExecutionReceipt {
        _=try CanonicalBytes.hex(actionHash,count:32)
        return try await perform("/v1/receipts?actionHash=\(actionHash)")
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
    private let session:URLSession
    private let chainID:UInt64
    init(url:String,chainID:UInt64=11_155_111,sessionConfiguration:URLSessionConfiguration = .ephemeral){
        self.url=URL(string:url);self.chainID=chainID
        session=URLSession(configuration:sessionConfiguration,delegate:NoRedirects(),delegateQueue:nil)
    }
    struct Log:Decodable,Sendable {let address:String;let topics:[String];let data:String}
    struct Receipt:Decodable,Sendable {let status:String;let transactionHash:String;let blockHash:String;let blockNumber:String;let logs:[Log]}
    private struct Block:Decodable {let hash:String;let number:String;let timestamp:String?}
    private struct RPCError:Decodable {let code:Int;let message:String}
    private struct Response<T:Decodable>:Decodable {let jsonrpc:String;let id:Int;let result:T?;let error:RPCError?}
    private func call<T:Decodable>(method:String,params:[Any]) async throws -> T? {
        guard let url,url.scheme == "https" else {throw ProductError.unavailable("Settlement RPC is not configured.")}
        var request=URLRequest(url:url);request.httpMethod="POST";request.timeoutInterval=20
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.httpBody=try JSONSerialization.data(withJSONObject:["jsonrpc":"2.0","id":1,"method":method,"params":params])
        let (bytes,response)=try await session.bytes(for:request)
        defer { bytes.task.cancel() }
        guard let http=response as? HTTPURLResponse,http.statusCode == 200,response.expectedContentLength < 1_000_000 else {throw ProductError.invalidResponse}
        var data=Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 1_000_000 else { throw ProductError.invalidResponse }
            data.append(byte)
        }
        let decoded=try JSONDecoder().decode(Response<T>.self,from:data)
        guard decoded.jsonrpc=="2.0",decoded.id==1 else{throw ProductError.invalidResponse}
        guard decoded.error == nil else {throw ProductError.unavailable("Could not verify the operation through Settlement RPC.")}
        return decoded.result
    }
    func ensureNetwork() async throws {
        let chain:String?=try await call(method:"eth_chainId",params:[])
        guard [UInt64(11_155_111),5_042_002,84_532].contains(chainID), chain?.lowercased() == "0x" + String(chainID,radix:16) else {throw ProductError.unavailable("The connected network does not match this installation. Signing and payment have been stopped.")}
    }
    func confirm(hash:String) async throws -> Receipt {
        _=try CanonicalBytes.hex(hash,count:32)
        try await ensureNetwork()
        for _ in 0..<60 {
            try Task.checkCancellation()
            if let receipt:Receipt=try await call(method:"eth_getTransactionReceipt",params:[hash]) {
                guard receipt.transactionHash.lowercased() == hash.lowercased(),receipt.status == "0x1" else {
                    throw ProductError.unavailable("The transaction reverted. It has not been recorded as successful.")
                }
                let latest:String?=try await call(method:"eth_blockNumber",params:[])
                guard let height=UInt64(receipt.blockNumber.dropFirst(2),radix:16),height<UInt64.max,
                      let head=latest.flatMap({UInt64($0.dropFirst(2),radix:16)}) else{throw ProductError.invalidResponse}
                if head>height {
                    let block:Block?=try await call(method:"eth_getBlockByNumber",params:[receipt.blockNumber,false])
                    guard block?.hash.lowercased()==receipt.blockHash.lowercased() else{throw ProductError.invalidResponse}
                    return receipt
                }
            }
            try await Task.sleep(for:.seconds(2))
        }
        throw ProductError.unavailable("The transaction was submitted, but confirmation is pending. Check its history before sending again.")
    }
    func confirmExecution(_ result:ExecutionReceipt,pending:PendingExecution,vault:String) async throws {
        let receipt=try await confirm(hash:result.transactionHash)
        guard let spent=UInt64(result.spentAfter),let height=UInt64(receipt.blockNumber.dropFirst(2),radix:16),
              String(height)==result.blockNumber else{throw ProductError.invalidResponse}
        let matches=receipt.logs.filter { log in
            (try? ExecutionEvidence.validate(address:log.address,topics:log.topics,data:log.data,vault:vault,
                actionHash:pending.actionHash,proofHash:pending.proofHash,spentAfter:spent,action:pending.submission?.action)) != nil
        }
        guard matches.count==1 else{throw ProductError.invalidResponse}
    }
    func confirmShop(_ order: AgeShopOrder) async throws -> String {
        guard chainID == AgeShopProtocol.chainID, order.chainId == chainID,
              order.token.lowercased() == AgeShopProtocol.token, order.amount == AgeShopProtocol.amount,
              let transaction = order.paymentTransaction else { throw AgeShopError.invalidPayment }
        let receipt = try await confirm(hash: transaction)
        try AgeShopReceipt.validate(order: order, logs: receipt.logs.map { .init(address: $0.address, topics: $0.topics, data: $0.data) })
        return receipt.blockHash.lowercased()
    }
    func finalizedShopHeight() async throws -> UInt64 {
        guard chainID == AgeShopProtocol.chainID else { throw AgeShopError.invalidPayment }
        try await ensureNetwork()
        let block: Block? = try await call(method: "eth_getBlockByNumber", params: ["finalized", false])
        guard let block, block.number.hasPrefix("0x"), let height = UInt64(block.number.dropFirst(2), radix: 16) else { throw ProductError.invalidResponse }
        return height
    }
    func confirmUnusedShop(_ order: AgeShopOrder, validBefore: UInt64, blockNumber: UInt64) async throws -> String {
        guard chainID == AgeShopProtocol.chainID, order.chainId == chainID,
              order.token.lowercased() == AgeShopProtocol.token,
              validBefore == order.paymentValidBefore, validBefore > order.createdAt,
              validBefore <= order.expiresAt else { throw AgeShopError.invalidPayment }
        let height = "0x" + String(blockNumber, radix: 16)
        let block: Block? = try await call(method: "eth_getBlockByNumber", params: [height, false])
        guard let block, block.number.lowercased() == height, let time = block.timestamp,
              time.hasPrefix("0x"), let timestamp = UInt64(time.dropFirst(2), radix: 16), timestamp >= validBefore else { throw ProductError.invalidResponse }
        _ = try CanonicalBytes.hex(block.hash, count: 32)
        let payer = try CanonicalBytes.hexString(CanonicalBytes.hex(order.payer, count: 20)).dropFirst(2)
        let nonce = try CanonicalBytes.hexString(CanonicalBytes.hex(order.paymentNonce, count: 32)).dropFirst(2)
        // ERC-3009 authorizationState(address,bytes32); selector independently
        // checked against viem and the public ERC-3009 specification.
        let data = "0xe94a0102" + String(repeating: "0", count: 24) + payer + nonce
        let state: String? = try await call(method: "eth_call", params: [["to": AgeShopProtocol.token, "data": data], height])
        guard state == "0x" + String(repeating: "0", count: 64) else { throw AgeShopError.invalidPayment }
        return block.hash.lowercased()
    }
}
