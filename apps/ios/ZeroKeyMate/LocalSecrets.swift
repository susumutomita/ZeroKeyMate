import CryptoKit
import Foundation
import Security
import MateCore

enum LocalSecrets {
    private static let service = "com.zerokeymate.private-state"
    static func read<T: Decodable>(_ type: T.Type, key: String) throws -> T? {
        let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,
            kSecAttrService as String:service,kSecAttrAccount as String:key,kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]
        var result: CFTypeRef?
        let status=SecItemCopyMatching(query as CFDictionary,&result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data=result as? Data else { throw SecretError.storage(status) }
        return try JSONDecoder().decode(type,from:data)
    }
    static func write<T: Encodable>(_ value:T,key:String) throws {
        let data=try JSONEncoder().encode(value)
        let query:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:key]
        let update=SecItemUpdate(query as CFDictionary,[kSecValueData as String:data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw SecretError.storage(update) }
        var entry=query
        entry[kSecValueData as String]=data
        entry[kSecAttrAccessible as String]=kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status=SecItemAdd(entry as CFDictionary,nil)
        guard status == errSecSuccess else { throw SecretError.storage(status) }
    }
    static func delete(_ key:String) throws {
        let status=SecItemDelete([kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:key] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SecretError.storage(status) }
    }
    static func random32() throws -> Data {
        var bytes=[UInt8](repeating:0,count:32)
        guard SecRandomCopyBytes(kSecRandomDefault,bytes.count,&bytes) == errSecSuccess else { throw SecretError.random }
        return Data(bytes)
    }
    static func hash(_ bytes:Data) -> String { CanonicalBytes.hexString(Data(SHA256.hash(data:bytes))) }
}

enum SecretError: Error, LocalizedError {
    case storage(OSStatus), random
    var errorDescription:String? { "端末内の安全な保存領域を利用できません。端末のロックを解除して再試行してください。" }
}

struct StoredMandate: Codable, Sendable {
    let id:String
    let grant:MandateGrant
    let policy:PrivatePolicy
}

struct WalletRoles: Codable, Sendable {
    let userID:String
    var owner:String
    var agent:String?
}
