import Foundation
import LocalAuthentication
import MateCore
import PrivySDK

/// Only deterministic approval screens can call owner-signing methods.
/// The conversation model never receives this object or a wallet provider.
@MainActor
final class WalletService: ObservableObject {
    @Published private(set) var ownerAddress: String?
    @Published private(set) var agentAddress: String?
    @Published private(set) var isAuthenticated = false
    @Published private(set) var busy = false
    private let configuration: AppConfiguration
    private static var sharedPrivy: (any Privy)?
    private static var sharedCredentials: (String, String)?
    private var ownerWallet: (any EmbeddedEthereumWallet)?
    private var agentWallet: (any EmbeddedEthereumWallet)?
    private let rpc: EthereumRPC
    init(configuration: AppConfiguration) {
        self.configuration = configuration
        rpc = EthereumRPC(url: configuration.rpcURL,chainID:configuration.chainID)
    }
    private func client() async throws -> any Privy {
        guard configuration.walletConfigured else {
            throw ProductError.unavailable("Configure your Privy App ID and iOS Client ID. No wallet has been created yet.")
        }
        if let value = Self.sharedPrivy {
            guard let credentials = Self.sharedCredentials,
                  credentials.0 == configuration.privyAppID,
                  credentials.1 == configuration.privyClientID else {
                throw ProductError.unavailable("Privy credentials changed. Close and restart the app to use the saved connection settings.")
            }
            _ = await value.getAuthState()
            return value
        }
        let value = PrivySdk.initialize(config: PrivyConfig(appId: configuration.privyAppID,
            appClientId: configuration.privyClientID, loggingConfig: PrivyLoggingConfig(logLevel: .none)))
        Self.sharedPrivy = value
        Self.sharedCredentials = (configuration.privyAppID, configuration.privyClientID)
        _ = await value.getAuthState()
        return value
    }
    func restore() async throws {
        let sdk = try await client()
        guard let user = await sdk.getUser() else { isAuthenticated = false; return }
        isAuthenticated = true
        guard let roles = try LocalSecrets.read(WalletRoles.self, key: "wallet-roles"), roles.userID == user.id else { return }
        ownerWallet = user.embeddedEthereumWallets.first { $0.address.lowercased() == roles.owner.lowercased() }
        agentWallet = user.embeddedEthereumWallets.first { $0.address.lowercased() == roles.agent?.lowercased() }
        ownerAddress = ownerWallet?.address; agentAddress = agentWallet?.address
    }
    func sendCode(email: String) async throws {
        guard !busy else { throw ProductError.busy }
        busy = true; defer { busy = false }
        let sdk = try await client()
        try await sdk.email.sendCode(to: email.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    func login(email: String, code: String) async throws {
        guard !busy else { throw ProductError.busy }
        busy = true; defer { busy = false }
        let sdk = try await client()
        _ = try await sdk.email.loginWithCode(code, sentTo: email.trimmingCharacters(in: .whitespacesAndNewlines))
        try await restore()
    }
    func prepareWallets() async throws {
        guard !busy else { throw ProductError.busy }
        busy = true; defer { busy = false }
        let sdk = try await client()
        guard let user = await sdk.getUser() else { throw ProductError.unavailable("Sign in with your email first.") }
        isAuthenticated = true
        var roles = try LocalSecrets.read(WalletRoles.self, key: "wallet-roles")
        if roles?.userID != user.id { roles = nil }
        if let roles {
            guard let wallet = user.embeddedEthereumWallets.first(where: { $0.address.lowercased() == roles.owner.lowercased() }) else {
                throw ProductError.unavailable("The registered owner wallet could not be found. Its key will not be replaced automatically.")
            }
            ownerWallet = wallet
        } else {
            ownerWallet = user.embeddedEthereumWallets.sorted { $0.hdWalletIndex < $1.hdWalletIndex }.first
            if ownerWallet == nil { ownerWallet = try await user.createEthereumWallet() }
            guard let ownerWallet else { throw ProductError.invalidResponse }
            roles = WalletRoles(userID: user.id, owner: ownerWallet.address, agent: nil)
            try LocalSecrets.write(roles, key: "wallet-roles")
        }
        if let address = roles?.agent {
            guard let wallet = user.embeddedEthereumWallets.first(where: { $0.address.lowercased() == address.lowercased() }) else {
                throw ProductError.unavailable("The registered execution key could not be found. Revoke the mandate before setting it up again.")
            }
            agentWallet = wallet
        } else {
            agentWallet = try await user.createEthereumWallet(allowAdditional: true)
            roles?.agent = agentWallet?.address
            try LocalSecrets.write(roles, key: "wallet-roles")
        }
        ownerAddress = ownerWallet?.address; agentAddress = agentWallet?.address
        guard ownerAddress != agentAddress else { throw ProductError.invalidResponse }
    }
    private func authenticateOwner(reason: String) async throws {
        let context = LAContext(); var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw ProductError.unavailable("Owner approval requires your device passcode or Face ID.")
        }
        guard try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) else { throw ProductError.cancelled }
    }
    private var signingDomain: EthereumRpcRequest.EIP712TypedData.EIP712Domain {
        .init(name: "ZeroKey Mate", version: "1", chainId: Int(configuration.chainID), verifyingContract: configuration.vault)
    }
    func signGrant(_ grant: MandateGrant,validateApproval:() throws -> Void) async throws -> String {
        guard let ownerWallet, ownerWallet.address.lowercased() == grant.owner.lowercased(),
              grant.agent.lowercased() == agentAddress?.lowercased(), configuration.paymentsConfigured else { throw ProductError.invalidResponse }
        try validateApproval()
        try await rpc.ensureNetwork()
        try validateApproval()
        try await authenticateOwner(reason: "Authorize Mate to act under the displayed terms")
        try validateApproval()
        let typed = EthereumRpcRequest.EIP712TypedData(domain: signingDomain, primaryType: "Grant", types: ["Grant": [
            .init("owner", type: "address"), .init("agent", type: "address"), .init("policyHash", type: "bytes32"),
            .init("validUntil", type: "uint64"), .init("nonce", type: "uint256")
        ]], message: ["owner": grant.owner, "agent": grant.agent, "policyHash": grant.policyHash,
                      "validUntil": String(grant.validUntil), "nonce": grant.nonce])
        return try await ownerWallet.provider.request(.ethSignTypedDataV4(address: ownerWallet.address, typedData: typed))
    }
    func signAction(hash: String,validateApproval:() throws -> Void) async throws -> String {
        guard let agentWallet, configuration.paymentsConfigured else { throw ProductError.unavailable("The execution wallet is not configured.") }
        _ = try CanonicalBytes.hex(hash, count: 32)
        try await rpc.ensureNetwork()
        try validateApproval()
        let typed = EthereumRpcRequest.EIP712TypedData(domain: signingDomain, primaryType: "Execution",
            types: ["Execution": [.init("actionHash", type: "bytes32")]], message: ["actionHash": hash])
        return try await agentWallet.provider.request(.ethSignTypedDataV4(address: agentWallet.address, typedData: typed))
    }
    func signName(label: String, nonce: String, expiresAt: UInt64) async throws -> String {
        guard let ownerWallet, let agentAddress, configuration.paymentsConfigured,
              configuration.chainID == 11_155_111, !configuration.ensParent.isEmpty,
              label.range(of: "^[a-z0-9][a-z0-9-]{1,30}[a-z0-9]$", options: .regularExpression) != nil else { throw ProductError.invalidResponse }
        _ = try CanonicalBytes.hex(nonce, count: 32)
        try await authenticateOwner(reason: "Register this name for Mate's public address")
        let message = "ZeroKey Mate name registration\nchain:11155111\nvault:\(configuration.vault.lowercased())\nname:\(label).\(configuration.ensParent)\nowner:\(ownerWallet.address.lowercased())\nagent:\(agentAddress.lowercased())\nnonce:\(nonce.lowercased())\nexpires:\(expiresAt)"
        return try await ownerWallet.provider.request(.personalSign(message: CanonicalBytes.hexString(Data(message.utf8)), address: ownerWallet.address))
    }
    enum FundingOperation { case approve(UInt64), deposit(UInt64), withdraw(UInt64), revoke(String) }
    func send(_ operation: FundingOperation,validateApproval:() throws -> Void) async throws -> String {
        guard let ownerWallet, configuration.paymentsConfigured else { throw ProductError.unavailable("Complete signing and settlement connection setup first.") }
        guard let url = Bundle.main.url(forResource: "Selectors", withExtension: "json"),
              let selectors = try? JSONDecoder().decode([String:String].self, from: Data(contentsOf: url)) else { throw ProductError.invalidResponse }
        let name: String, to: String, parameters: String, reason: String
        func word(_ value: UInt64) -> String { let hex = String(value, radix: 16); return String(repeating: "0", count: 64 - hex.count) + hex }
        switch operation {
        case .approve(let amount):
            guard amount > 0 else { throw MandateError.invalidAmount }
            name = "approve(address,uint256)"; to = configuration.token
            parameters = String(repeating: "0", count: 24) + configuration.vault.dropFirst(2).lowercased() + word(amount)
            reason = "Approve only the displayed test USDC deposit amount"
        case .deposit(let amount):
            guard amount > 0 else { throw MandateError.invalidAmount }
            name = "deposit(uint256)"; to = configuration.vault; parameters = word(amount); reason = "Deposit test USDC into the execution account"
        case .withdraw(let amount):
            guard amount > 0 else { throw MandateError.invalidAmount }
            name = "withdraw(uint256)"; to = configuration.vault; parameters = word(amount); reason = "Return test USDC to the owner's wallet"
        case .revoke(let id):
            _ = try CanonicalBytes.hex(id, count: 32)
            name = "revoke(bytes32)"; to = configuration.vault; parameters = String(id.dropFirst(2)); reason = "Revoke Mate's mandate on-chain"
        }
        guard let selector = selectors[name], selector.utf8.count == 10 else { throw ProductError.invalidResponse }
        try validateApproval()
        try await rpc.ensureNetwork()
        try validateApproval()
        try await authenticateOwner(reason: reason)
        try validateApproval()
        await ownerWallet.provider.switchChain(chainId: Int(configuration.chainID), rpcUrl: configuration.rpcURL)
        try validateApproval()
        let transaction = EthereumRpcRequest.UnsignedEthTransaction(from: ownerWallet.address, to: to,
            data: selector + parameters, value: .int(0), chainId: .int(Int(configuration.chainID)))
        return try await ownerWallet.provider.request(.ethSendTransaction(transaction: transaction))
    }
}
