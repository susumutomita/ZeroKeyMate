import CryptoKit
import Foundation

/// Large, explicitly approved requests are sealed to a device-only Keychain key.
/// Raw camera frames and microphone recordings never reach this store.
enum PrivateFiles {
    private static func directory() throws -> URL {
        var url = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                             appropriateFor: nil, create: true)
            .appendingPathComponent("PrivatePending", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete])
        var attributes = URLResourceValues(); attributes.isExcludedFromBackup = true
        try url.setResourceValues(attributes)
        return url
    }
    private static func key(create: Bool) throws -> SymmetricKey? {
        if let bytes = try LocalSecrets.read(Data.self, key: "private-file-key") {
            guard bytes.count == 32 else { throw ProductError.invalidResponse }
            return SymmetricKey(data: bytes)
        }
        guard create else { return nil }
        let bytes = try LocalSecrets.random32()
        try LocalSecrets.write(bytes, key: "private-file-key")
        return SymmetricKey(data: bytes)
    }
    private static func file(_ name: String) throws -> URL {
        try directory().appendingPathComponent(LocalSecrets.hash(Data(name.utf8)) + ".sealed")
    }
    static func write<T: Encodable>(_ value: T, name: String) throws {
        guard let key = try key(create: true) else { throw ProductError.invalidResponse }
        let data = try JSONEncoder().encode(value)
        guard data.count <= 16_000_000 else { throw ProductError.invalidResponse }
        let sealed = try AES.GCM.seal(data, using: key, authenticating: Data(name.utf8))
        guard let packed = sealed.combined else { throw ProductError.invalidResponse }
        try packed.write(to: file(name), options: [.atomic, .completeFileProtection])
    }
    static func read<T: Decodable>(_ type: T.Type, name: String) throws -> T? {
        let url = try file(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let key = try key(create: false),
              (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 16_000_100 else {
            throw ProductError.invalidResponse
        }
        let bytes = try Data(contentsOf: url)
        let opened = try AES.GCM.open(AES.GCM.SealedBox(combined: bytes), using: key, authenticating: Data(name.utf8))
        return try JSONDecoder().decode(type, from: opened)
    }
    static func delete(_ name: String) throws {
        let url = try file(name)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
