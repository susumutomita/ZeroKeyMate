import Foundation
import MateCore

struct AppConfiguration: Codable, Sendable {
    var apiURL: String
    var apiToken: String
    var privyAppID: String
    var privyClientID: String
    var rpcURL: String
    var vault: String
    var token: String
    var ensParent: String = ""
    let chainID: UInt64

    static func load() -> AppConfiguration {
        guard let url = Bundle.main.url(forResource: "Configuration", withExtension: "json"),
              let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(Self.self, from: data) else {
            return Self(apiURL: "http://127.0.0.1:8787", apiToken: "", privyAppID: "", privyClientID: "",
                rpcURL: "https://ethereum-sepolia-rpc.publicnode.com", vault: "",
                token: "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238", chainID: 11_155_111)
        }
        return value
    }
    var walletConfigured: Bool { !privyAppID.isEmpty && !privyClientID.isEmpty }
    var paymentsConfigured: Bool {
        chainID == 11_155_111 && apiToken.count >= 32
            && (try? CanonicalBytes.hex(vault, count: 20)) != nil
            && vault.lowercased() != "0x" + String(repeating: "00", count: 20)
            && token.lowercased() == "0x1c7d4b196cb0c7b01d743fbc6116a902379c7238"
            && URL(string: rpcURL)?.scheme == "https"
    }
    var storageScope: String {
        LocalSecrets.hash(Data("\(chainID):\(vault.lowercased()):\(privyAppID)".utf8))
    }
}

enum ProductError: Error, LocalizedError {
    case unavailable(String), invalidResponse, busy, cancelled, transactionReverted(String)
    var errorDescription: String? {
        switch self {
        case .unavailable(let message): return message
        case .invalidResponse: return "応答を検証できませんでした。操作は完了扱いにしていません。"
        case .busy: return "実行中の操作が終わってから再試行してください。"
        case .cancelled: return "外部送信前に操作を中止しました。"
        case .transactionReverted(let hash): return "取引はチェーン上でrevertしました。成功として記録していません。\n" + hash
        }
    }
}
