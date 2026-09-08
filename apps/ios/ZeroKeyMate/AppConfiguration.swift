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
    var ensParent:String = ""
    var chainID:UInt64

    static func load() -> AppConfiguration {
        if let saved=try? LocalSecrets.read(Self.self,key:"connection-settings") { return saved }
        guard let url=Bundle.main.url(forResource:"Configuration",withExtension:"json"),
              let data=try? Data(contentsOf:url),let value=try? JSONDecoder().decode(Self.self,from:data) else {
            return Self(apiURL:"http://127.0.0.1:8787",apiToken:"",privyAppID:"",privyClientID:"",
                        rpcURL:"https://ethereum-sepolia-rpc.publicnode.com",vault:"",token:"",chainID:11_155_111)
        }
        return value
    }
    var networkName:String { chainID == 5_042_002 ? "Arc Testnet" : chainID == 11_155_111 ? "Sepolia testnet" : "Unsupported network" }
    var explorerURL:String { chainID == 5_042_002 ? "https://testnet.arcscan.app" : "https://sepolia.etherscan.io" }
    var expectedToken:String? {
        switch chainID {
        case 5_042_002: return "0x3600000000000000000000000000000000000000"
        case 11_155_111: return "0x1c7d4b196cb0c7b01d743fbc6116a902379c7238"
        default: return nil
        }
    }
    func stateKey(_ name:String) -> String {
        // Preserve recoverability of the original Sepolia installation.
        chainID == 11_155_111 ? name : "\(chainID):\(vault.lowercased()):\(name)"
    }
    var walletConfigured:Bool { !privyAppID.isEmpty && !privyClientID.isEmpty }
    var paymentsConfigured:Bool {
        expectedToken != nil && apiToken.count>=32
        && (try? CanonicalBytes.hex(vault,count:20))?.contains(where:{$0 != 0}) == true
        && token.lowercased()==expectedToken
        && URL(string:rpcURL)?.scheme == "https"
    }
}

enum ProductError: Error, LocalizedError {
    case unavailable(String), invalidResponse, busy, cancelled
    var errorDescription:String? {
        switch self {
        case .unavailable(let message):return message
        case .invalidResponse:return "The response could not be verified. The operation has not been marked complete."
        case .busy:return "Wait for the current operation to finish, then try again."
        case .cancelled:return "The operation was cancelled."
        }
    }
}
