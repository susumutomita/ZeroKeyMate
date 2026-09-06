import Foundation
import MateCore

struct AppConfiguration: Codable, Sendable {
    var apiURL:String
    var apiToken:String
    var privyAppID:String
    var privyClientID:String
    var rpcURL:String
    var vault:String
    var token:String
    let chainID:UInt64

    static func load() -> AppConfiguration {
        guard let url=Bundle.main.url(forResource:"Configuration",withExtension:"json"),
              let data=try? Data(contentsOf:url),let value=try? JSONDecoder().decode(Self.self,from:data) else {
            return Self(apiURL:"http://127.0.0.1:8787",apiToken:"",privyAppID:"",privyClientID:"",
                        rpcURL:"https://ethereum-sepolia-rpc.publicnode.com",vault:"",token:"",chainID:11_155_111)
        }
        return value
    }
    var walletConfigured:Bool { !privyAppID.isEmpty && !privyClientID.isEmpty }
    var paymentsConfigured:Bool {
        chainID == 11_155_111 && !apiToken.isEmpty
        && (try? CanonicalBytes.hex(vault,count:20)) != nil
        && (try? CanonicalBytes.hex(token,count:20)) != nil
        && URL(string:rpcURL)?.scheme == "https"
    }
}

enum ProductError: Error, LocalizedError {
    case unavailable(String), invalidResponse, busy, cancelled
    var errorDescription:String? {
        switch self {
        case .unavailable(let message):return message
        case .invalidResponse:return "応答を検証できませんでした。操作は完了扱いにしていません。"
        case .busy:return "実行中の操作が終わってから再試行してください。"
        case .cancelled:return "操作を中止しました。"
        }
    }
}
