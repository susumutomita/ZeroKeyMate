import Foundation
import LocalAuthentication
import MateCore
import PrivySDK

struct SignedWalletOperation: Codable, Sendable {
    let raw: String
    let hash: String
    let signer: String
    let title: String
    let revokedMandate: String?
}

/// Only deterministic approval screens can call owner-signing methods.
/// The conversation model never receives this object or a wallet provider.
@MainActor
final class WalletService: ObservableObject {
    @Published private(set) var ownerAddress: String?
    @Published private(set) var agentAddress: String?
    @Published private(set) var isAuthenticated = false
    @Published private(set) var busy = false
    private let configuration: AppConfiguration
    private var privy: (any Privy)?
    private var ownerWallet: (any EmbeddedEthereumWallet)?
    private var agentWallet: (any EmbeddedEthereumWallet)?
    private let rpc: EthereumRPC
    init(configuration: AppConfiguration) {
        self.configuration = configuration
        rpc = EthereumRPC(url: configuration.rpcURL)
    }
    private func client() throws -> any Privy {
        guard configuration.walletConfigured else {
            throw ProductError.unavailable("PrivyのApp IDとiOS Client IDを設定してください。ウォレットはまだ作成されていません。")
        }
        if let privy { return privy }
        let value = PrivySdk.initialize(config: PrivyConfig(appId: configuration.privyAppID,
            appClientId: configuration.privyClientID, loggingConfig: PrivyLoggingConfig(logLevel: .none)))
        privy = value
        return value
    }
    func restore() async throws {
        guard let user = await (try client()).getUser() else {
            isAuthenticated = false; ownerWallet = nil; agentWallet = nil
            ownerAddress = nil; agentAddress = nil; return
        }
        isAuthenticated = true
        guard let roles = try LocalSecrets.read(WalletRoles.self, key: "wallet-roles-" + configuration.privyAppID), roles.userID == user.id else { return }
        ownerWallet = user.embeddedEthereumWallets.first { $0.address.lowercased() == roles.owner.lowercased() }
        agentWallet = user.embeddedEthereumWallets.first { $0.address.lowercased() == roles.agent?.lowercased() }
        ownerAddress = ownerWallet?.address; agentAddress = agentWallet?.address
    }
    func sendCode(email: String) async throws {
        guard !busy else { throw ProductError.busy }
        busy = true; defer { busy = false }
        try await client().email.sendCode(to: email.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    func login(email: String, code: String) async throws {
        guard !busy else { throw ProductError.busy }
        busy = true; defer { busy = false }
        _ = try await client().email.loginWithCode(code, sentTo: email.trimmingCharacters(in: .whitespacesAndNewlines))
        try await restore()
    }
    func prepareWallets() async throws {
        guard !busy else { throw ProductError.busy }
        busy = true; defer { busy = false }
        guard let user = await (try client()).getUser() else { throw ProductError.unavailable("先にメールアドレスでログインしてください。") }
        isAuthenticated = true
        var roles = try LocalSecrets.read(WalletRoles.self, key: "wallet-roles-" + configuration.privyAppID)
        if roles?.userID != user.id { roles = nil }
        if let roles {
            guard let wallet = user.embeddedEthereumWallets.first(where: { $0.address.lowercased() == roles.owner.lowercased() }) else {
                throw ProductError.unavailable("登録済みの所有者ウォレットが見つかりません。鍵の自動置換は行いません。")
            }
            ownerWallet = wallet
        } else {
            ownerWallet = user.embeddedEthereumWallets.sorted { $0.hdWalletIndex < $1.hdWalletIndex }.first
            if ownerWallet == nil { ownerWallet = try await user.createEthereumWallet() }
            guard let ownerWallet else { throw ProductError.invalidResponse }
            roles = WalletRoles(userID: user.id, owner: ownerWallet.address, agent: nil)
            try LocalSecrets.write(roles, key: "wallet-roles-" + configuration.privyAppID)
        }
        if let address = roles?.agent {
            guard let wallet = user.embeddedEthereumWallets.first(where: { $0.address.lowercased() == address.lowercased() }) else {
                throw ProductError.unavailable("登録済みの実行キーが見つかりません。委任を失効させてから再設定してください。")
            }
            agentWallet = wallet
        } else {
            agentWallet = try await user.createEthereumWallet(allowAdditional: true)
            roles?.agent = agentWallet?.address
            try LocalSecrets.write(roles, key: "wallet-roles-" + configuration.privyAppID)
        }
        ownerAddress = ownerWallet?.address; agentAddress = agentWallet?.address
        guard ownerAddress != agentAddress else { throw ProductError.invalidResponse }
    }
    private func authenticateOwner(reason: String) async throws {
        let context = LAContext(); var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw ProductError.unavailable("所有者の承認には端末のパスコードまたはFace IDが必要です。")
        }
        guard try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) else { throw ProductError.cancelled }
    }
    private static let domainTypes: [EthereumRpcRequest.EIP712TypedData.EIP712Type] = [
        .init("name",type:"string"), .init("version",type:"string"),
        .init("chainId",type:"uint256"), .init("verifyingContract",type:"address")
    ]
    private var signingDomain: EthereumRpcRequest.EIP712TypedData.EIP712Domain {
        .init(name: "ZeroKey Mate", version: "1", chainId: Int(configuration.chainID), verifyingContract: configuration.vault)
    }
    func signGrant(_ grant: MandateGrant) async throws -> String {
        guard let ownerWallet, ownerWallet.address.lowercased() == grant.owner.lowercased(),
              grant.agent.lowercased() == agentAddress?.lowercased(), configuration.paymentsConfigured else { throw ProductError.invalidResponse }
        try await rpc.ensureSepolia()
        try await authenticateOwner(reason: "表示した条件でMateに実行権限を与えます")
        await ownerWallet.provider.switchChain(chainId:11_155_111,rpcUrl:configuration.rpcURL)
        let typed = EthereumRpcRequest.EIP712TypedData(domain: signingDomain, primaryType: "Grant", types: ["EIP712Domain": Self.domainTypes, "Grant": [
            .init("owner", type: "address"), .init("agent", type: "address"), .init("policyHash", type: "bytes32"),
            .init("validUntil", type: "uint64"), .init("nonce", type: "uint256")
        ]], message: ["owner": grant.owner, "agent": grant.agent, "policyHash": grant.policyHash,
                      "validUntil": String(grant.validUntil), "nonce": grant.nonce])
        return try await ownerWallet.provider.request(.ethSignTypedDataV4(address: ownerWallet.address, typedData: typed))
    }
    func signAction(hash: String) async throws -> String {
        guard let agentWallet, configuration.paymentsConfigured else { throw ProductError.unavailable("実行用ウォレットが未設定です。") }
        _ = try CanonicalBytes.hex(hash, count: 32)
        try await rpc.ensureSepolia()
        await agentWallet.provider.switchChain(chainId:11_155_111,rpcUrl:configuration.rpcURL)
        let typed = EthereumRpcRequest.EIP712TypedData(domain: signingDomain, primaryType: "Execution",
            types: ["EIP712Domain": Self.domainTypes, "Execution": [.init("actionHash", type: "bytes32")]], message: ["actionHash": hash])
        return try await agentWallet.provider.request(.ethSignTypedDataV4(address: agentWallet.address, typedData: typed))
    }
    func signName(label: String, nonce: String, expiresAt: UInt64) async throws -> String {
        guard let ownerWallet, let agentAddress, configuration.paymentsConfigured,
              label.range(of: "^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$", options: .regularExpression) != nil else { throw ProductError.invalidResponse }
        _ = try CanonicalBytes.hex(nonce, count: 32)
        try await authenticateOwner(reason: "この名前をMateの公開アドレスとして登録します")
        let message = "ZeroKey Mate name registration\nchain:11155111\nvault:\(configuration.vault.lowercased())\nparent:\(configuration.ensParent)\nlabel:\(label)\nowner:\(ownerWallet.address.lowercased())\nagent:\(agentAddress.lowercased())\nnonce:\(nonce.lowercased())\nexpires:\(expiresAt)"
        return try await ownerWallet.provider.request(.personalSign(message: CanonicalBytes.hexString(Data(message.utf8)), address: ownerWallet.address))
    }
    enum FundingOperation { case approve(UInt64), deposit(UInt64), withdraw(UInt64), revoke(String) }
    func prepare(_ operation: FundingOperation) async throws -> SignedWalletOperation {
        guard let ownerWallet, configuration.paymentsConfigured else { throw ProductError.unavailable("署名とSepoliaの接続設定を完了してください。") }
        guard let url = Bundle.main.url(forResource: "Selectors", withExtension: "json"),
              let selectors = try? JSONDecoder().decode([String:String].self, from: Data(contentsOf: url)) else { throw ProductError.invalidResponse }
        let name: String, to: String, parameters: String, reason: String
        func word(_ value: UInt64) -> String { let hex = String(value, radix: 16); return String(repeating: "0", count: 64 - hex.count) + hex }
        switch operation {
        case .approve(let amount):
            guard amount > 0 else { throw MandateError.invalidAmount }
            name = "approve(address,uint256)"; to = configuration.token
            parameters = String(repeating: "0", count: 24) + configuration.vault.dropFirst(2).lowercased() + word(amount)
            reason = "テストUSDC \(TokenAmount(units:amount).display) の預け入れだけを承認します"
        case .deposit(let amount):
            guard amount > 0 else { throw MandateError.invalidAmount }
            name = "deposit(uint256)"; to = configuration.vault; parameters = word(amount); reason = "テストUSDC \(TokenAmount(units:amount).display) を実行用口座に預けます"
        case .withdraw(let amount):
            guard amount > 0 else { throw MandateError.invalidAmount }
            name = "withdraw(uint256)"; to = configuration.vault; parameters = word(amount); reason = "テストUSDC \(TokenAmount(units:amount).display) を所有者へ戻します"
        case .revoke(let id):
            _ = try CanonicalBytes.hex(id, count: 32)
            name = "revoke(bytes32)"; to = configuration.vault; parameters = String(id.dropFirst(2)); reason = "Mateへの委任をオンチェーンで失効させます"
        }
        guard let selector = selectors[name], selector.utf8.count == 10 else { throw ProductError.invalidResponse }
        let revoked: String?
        if case .revoke(let id)=operation { revoked=id } else { revoked=nil }
        return try await signTransaction(wallet:ownerWallet,to:to,data:selector+parameters,reason:reason,revoked:revoked,ownerApproval:true)
    }
    private func signTransaction(wallet: any EmbeddedEthereumWallet, to: String, data: String,
                                 reason: String, revoked: String? = nil, ownerApproval: Bool) async throws -> SignedWalletOperation {
        let gas=try await rpc.prepareCall(from:wallet.address,to:to,data:data)
        if ownerApproval { try await authenticateOwner(reason:reason) }
        await wallet.provider.switchChain(chainId:11_155_111,rpcUrl:configuration.rpcURL)
        let transaction=EthereumRpcRequest.UnsignedEthTransaction(from:wallet.address,to:to,
            nonce:.hexadecimalNumber(gas.nonce),gasLimit:.hexadecimalNumber(gas.gas),gasPrice:.hexadecimalNumber(gas.gasPrice),
            data:data,value:.int(0),chainId:.int(11_155_111),type:0)
        let raw=try await wallet.provider.request(.ethSignTransaction(transaction:transaction))
        guard raw.utf8.count>180,raw.utf8.count<=32_770,raw.utf8.count%2==0 else { throw ProductError.invalidResponse }
        let bytes=try CanonicalBytes.hex(raw,count:(raw.utf8.count-2)/2)
        guard let first=bytes.first,first>=0xc0 else { throw ProductError.invalidResponse }
        return SignedWalletOperation(raw:raw,hash:CanonicalBytes.hexString(EthereumKeccak.digest(bytes)),
            signer:wallet.address,title:reason,revokedMandate:revoked)
    }
    func prepareAvatar(identity: MateIdentity, url: String) async throws -> SignedWalletOperation {
        guard let agentWallet,let resolver=identity.resolver,
              identity.owner.lowercased()==ownerAddress?.lowercased(),identity.address.lowercased()==agentWallet.address.lowercased(),
              identity.name.hasSuffix("."+configuration.ensParent),
              let location=URL(string:url),location.scheme=="https",location.user==nil,location.password==nil,
              url.utf8.count<=2048 else { throw ProductError.invalidResponse }
        let node=try EthereumABI.namehash(identity.name)
        let data=try EthereumABI.call("setText(bytes32,string,string)",[
            .word(node),.dynamic(Data("avatar".utf8)),.dynamic(Data(url.utf8))])
        return try await signTransaction(wallet:agentWallet,to:resolver,data:data,
            reason:"Mateの公開アイコンを更新します",ownerApproval:false)
    }
    func prepareAvatarPermission(identity: MateIdentity, enabled: Bool) async throws -> SignedWalletOperation {
        guard let ownerWallet,let agentAddress,let resolver=identity.resolver,
              identity.owner.lowercased()==ownerWallet.address.lowercased(),identity.address.lowercased()==agentAddress.lowercased(),
              identity.name.hasSuffix("."+configuration.ensParent) else { throw ProductError.invalidResponse }
        let data=try EthereumABI.call("authorizeTextRoles(bytes,string,address,bool)",[
            .dynamic(EthereumABI.dns(identity.name)),.dynamic(Data("avatar".utf8)),
            .word(EthereumABI.addressWord(agentAddress)),.word(EthereumABI.word(enabled ? 1 : 0))])
        return try await signTransaction(wallet:ownerWallet,to:resolver,data:data,
            reason:enabled ? "アイコンの編集だけをMateに許可します" : "Mateのアイコン編集権限を取り消します",ownerApproval:true)
    }

}
