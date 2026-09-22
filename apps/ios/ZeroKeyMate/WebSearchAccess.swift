import Foundation
import MateCore

/// Only credentials entered in the Web search settings are read. This actor
/// serializes disable/key replacement with requests and discards stale replies.
actor WebSearchAccess: WebSearchProviding {
    static let shared=WebSearchAccess()
    private static let keyName="brave-web-search-v1"
    private static let enabledName="web-search-enabled-v1"
    private var revision=0
    private var busy=false
    func enabled() -> Bool { UserDefaults.standard.bool(forKey:Self.enabledName) }
    func save(key: String) throws {
        guard BraveWebSearch.validKey(key) else { throw WebSearchError.credentials }
        try LocalSecrets.write(key, key:Self.keyName)
        UserDefaults.standard.set(true, forKey:Self.enabledName)
        revision += 1
    }
    func disable() throws {
        UserDefaults.standard.set(false, forKey:Self.enabledName)
        revision += 1
        try LocalSecrets.delete(Self.keyName)
    }
    func search(query: String, japanese: Bool) async throws -> WebSearchResult {
        guard enabled() else { throw WebSearchError.disabled }
        guard !busy else { throw WebSearchError.quota }
        guard let key=try LocalSecrets.read(String.self,key:Self.keyName) else { throw WebSearchError.credentials }
        // Count attempts before sending, including failed requests. A local guard,
        // not a provider billing guarantee; reinstallation can reset it.
        let defaults=UserDefaults.standard, day=Int(Date().timeIntervalSince1970/86_400)
        let used=defaults.integer(forKey:"web-search-day-v1")==day ? defaults.integer(forKey:"web-search-count-v1"):0
        guard used<20 else { throw WebSearchError.quota }
        defaults.set(day,forKey:"web-search-day-v1");defaults.set(used+1,forKey:"web-search-count-v1")
        let token=revision; busy=true
        defer { busy=false }
        let result=try await BraveWebSearch(apiKey:key).search(query:query,japanese:japanese)
        try Task.checkCancellation()
        guard token==revision,enabled() else { throw CancellationError() }
        return result
    }
}
