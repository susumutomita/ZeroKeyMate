import Foundation
import LocalAuthentication
import MateCore
import PrivySDK

/// The model never receives this object, a wallet provider, or signing tools.
@MainActor
final class WalletService:ObservableObject {
    @Published private(set) var ownerAddress:String?
    @Published private(set) var agentAddress:String?
    @Published private(set) var isAuthenticated=false
    @Published private(set) var busy=false
    private let configuration:AppConfiguration
    private var privy:(any Privy)?
    private var ownerWallet:(any EmbeddedEthereumWallet)?
    private var agentWallet:(any EmbeddedEthereumWallet)?
    private let rpc:EthereumRPC
    init(configuration:AppConfiguration) {self.configuration=configuration;rpc=EthereumRPC(url:configuration.rpcURL)}

    private func client() throws -> any Privy {
        guard configuration.walletConfigured else {throw ProductError.unavailable("PrivyのApp IDとiOS Client IDを設定してください。ウォレットはまだ作成されていません。")}
        if let privy {return privy}
        let value=PrivySdk.initialize(config:PrivyConfig(appId:configuration.privyAppID,appClientId:configuration.privyClientID,
                                                       loggingConfig:PrivyLoggingConfig(logLevel:.none)))
        privy=value;return value
    }
    func restore() async throws {
        let sdk=try client()
        guard let user=await sdk.getUser() else {isAuthenticated=false;return}
        isAuthenticated=true
        guard let roles=try LocalSecrets.read(WalletRoles.self,key:"wallet-roles"),roles.userID == user.id else {return}
        ownerWallet=user.embeddedEthereumWallets.first{$0.address.lowercased() == roles.owner.lowercased()}
        agentWallet=user.embeddedEthereumWallets.first{$0.address.lowercased() == roles.agent?.lowercased()}
        ownerAddress=ownerWallet?.address;agentAddress=agentWallet?.address
    }
    func sendCode(email:String) async throws {
        guard !busy else {throw ProductError.busy};busy=true;defer{busy=false}
        try await client().email.sendCode(to:email.trimmingCharacters(in:.whitespacesAndNewlines))
    }
    func login(email:String,code:String) async throws {
        guard !busy else {throw ProductError.busy};busy=true;defer{busy=false}
        _=try await client().email.loginWithCode(code,sentTo:email.trimmingCharacters(in:.whitespacesAndNewlines))
        try await restore()
    }
    /// Called only from an explicit wallet-setup action, never at application launch.
    func prepareWallets() async throws {
        guard !busy else {throw ProductError.busy};busy=true;defer{busy=false}
        let sdk=try client()
        guard let user=await sdk.getUser() else {throw ProductError.unavailable("先にメールアドレスでログインしてください。")}
        isAuthenticated=true
        var roles=try LocalSecrets.read(WalletRoles.self,key:"wallet-roles")
        if roles?.userID != user.id {roles=nil}
        if let roles {
            guard let wallet=user.embeddedEthereumWallets.first(where:{$0.address.lowercased()==roles.owner.lowercased()}) else {
                throw ProductError.unavailable("登録済みの所有者ウォレットが見つかりません。別の鍵への自動置換は行いません。")
            }
            ownerWallet=wallet
        } else {
            ownerWallet=user.embeddedEthereumWallets.sorted{$0.hdWalletIndex < $1.hdWalletIndex}.first
            if ownerWallet == nil {ownerWallet=try await user.createEthereumWallet()}
            guard let ownerWallet else {throw ProductError.invalidResponse}
            roles=WalletRoles(userID:user.id,owner:ownerWallet.address,agent:nil)
            try LocalSecrets.write(roles,key:"wallet-roles")
        }
        if let address=roles?.agent {
            guard let wallet=user.embeddedEthereumWallets.first(where:{$0.address.lowercased()==address.lowercased()}) else {
                throw ProductError.unavailable("登録済みの実行キーが見つかりません。委任を失効させてから再設定してください。")
            }
            agentWallet=wallet
        } else {
            agentWallet=try await user.createEthereumWallet(allowAdditional:true)
            roles?.agent=agentWallet?.address
            try LocalSecrets.write(roles,key:"wallet-roles")
        }
        ownerAddress=ownerWallet?.address;agentAddress=agentWallet?.address
        guard ownerAddress != agentAddress else {throw ProductError.invalidResponse}
    }
    private func authenticateOwner(reason:String) async throws {
        let context=LAContext()
        var error:NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication,error:&error) else {
            throw ProductError.unavailable("所有者の承認には端末のパスコードまたはFace IDが必要です。実機で設定してください。")
        }
        guard try await context.evaluatePolicy(.deviceOwnerAuthentication,localizedReason:reason) else {throw ProductError.cancelled}
    }
    func signGrant(_ grant:MandateGrant) async throws -> String {
        guard let ownerWallet,ownerWallet.address.lowercased()==grant.owner.lowercased(),
              grant.agent.lowercased()==agentAddress?.lowercased(),configuration.paymentsConfigured else {throw ProductError.invalidResponse}
        try await rpc.ensureSepolia()
        try await authenticateOwner(reason:"表示した条件でMateに実行権限を与えます")
        let document=try SigningDocument.grant(grant,chainID:configuration.chainID,vault:configuration.vault)
        return try await ownerWallet.provider.request(EthereumRpcRequest(method:"eth_signTypedData_v4",params:[ownerWallet.address,document]))
    }
    func signAction(hash:String) async throws -> String {
        guard let agentWallet,configuration.paymentsConfigured else {throw ProductError.unavailable("実行用ウォレットが未設定です。")}
        let document=try SigningDocument.execution(actionHash:hash,chainID:configuration.chainID,vault:configuration.vault)
        return try await agentWallet.provider.request(EthereumRpcRequest(method:"eth_signTypedData_v4",params:[agentWallet.address,document]))
    }
    func signName(label:String,nonce:String,expiresAt:UInt64) async throws -> String {
        guard let ownerWallet,let agentAddress,configuration.paymentsConfigured,
              label.range(of:"^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$",options:.regularExpression) != nil else {throw ProductError.invalidResponse}
        _=try CanonicalBytes.hex(nonce,count:32)
        try await authenticateOwner(reason:"この名前をMateの公開アドレスとして登録します")
        let message="ZeroKey Mate name registration\nchain:11155111\nvault:\(configuration.vault.lowercased())\nlabel:\(label)\nowner:\(ownerWallet.address.lowercased())\nagent:\(agentAddress.lowercased())\nnonce:\(nonce.lowercased())\nexpires:\(expiresAt)"
        let hex=CanonicalBytes.hexString(Data(message.utf8))
        return try await ownerWallet.provider.request(EthereumRpcRequest(method:"personal_sign",params:[hex,ownerWallet.address]))
    }
    enum FundingOperation {case approve(UInt64),deposit(UInt64),withdraw(UInt64),revoke(String)}
    func send(_ operation:FundingOperation) async throws -> String {
        guard let ownerWallet,configuration.paymentsConfigured else {throw ProductError.unavailable("署名とSepoliaの接続設定を完了してください。")}
        guard let url=Bundle.main.url(forResource:"Selectors",withExtension:"json"),
              let selectors=try? JSONDecoder().decode([String:String].self,from:Data(contentsOf:url)) else {throw ProductError.invalidResponse}
        let name:String,to:String,parameters:String,reason:String
        func word(_ value:UInt64)->String {let hex=String(value,radix:16);return String(repeating:"0",count:64-hex.count)+hex}
        switch operation {
        case .approve(let amount):
            guard amount>0 else {throw MandateError.invalidAmount}
            name="approve(address,uint256)";to=configuration.token
            parameters=String(repeating:"0",count:24)+configuration.vault.dropFirst(2).lowercased()+word(amount)
            reason="表示したテストUSDCの預入額だけを承認します"
        case .deposit(let amount):
            guard amount>0 else {throw MandateError.invalidAmount}
            name="deposit(uint256)";to=configuration.vault;parameters=word(amount);reason="テストUSDCをMateの実行用口座に預けます"
        case .withdraw(let amount):
            guard amount>0 else {throw MandateError.invalidAmount}
            name="withdraw(uint256)";to=configuration.vault;parameters=word(amount);reason="テストUSDCを所有者のウォレットへ戻します"
        case .revoke(let id):
            _=try CanonicalBytes.hex(id,count:32)
            name="revoke(bytes32)";to=configuration.vault;parameters=String(id.dropFirst(2));reason="Mateへの委任をオンチェーンで失効させます"
        }
        guard let selector=selectors[name],selector.utf8.count==10 else {throw ProductError.invalidResponse}
        try await rpc.ensureSepolia()
        try await authenticateOwner(reason:reason)
        await ownerWallet.provider.switchChain(chainId:11_155_111,rpcUrl:configuration.rpcURL)
        let transaction=["from":ownerWallet.address,"to":to,"chainId":"0xaa36a7","data":selector+parameters,"value":"0x0"]
        let json=String(decoding:try JSONSerialization.data(withJSONObject:transaction),as:UTF8.self)
        return try await ownerWallet.provider.request(EthereumRpcRequest(method:"eth_sendTransaction",params:[json]))
    }
}
