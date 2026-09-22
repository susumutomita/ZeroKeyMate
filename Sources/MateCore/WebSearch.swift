import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum WebSearchError: Error, Sendable, Equatable {
    case disabled, invalidQuery, credentials, quota, unavailable, invalidResponse
}

public struct WebSearchSource: Sendable, Equatable, Identifiable {
    public var id: String { url.absoluteString }
    public let title: String
    public let url: URL
    public let snippets: [String]
    public init(title: String, url: URL, snippets: [String]) {
        self.title=title; self.url=url; self.snippets=snippets
    }
}

public struct WebSearchResult: Sendable, Equatable {
    public let query: String
    public let sources: [WebSearchSource]
    public let fetchedAt: Date
    public init(query: String, sources: [WebSearchSource], fetchedAt: Date = Date()) {
        self.query=query; self.sources=sources; self.fetchedAt=fetchedAt
    }
}

public protocol WebSearchProviding: Sendable {
    func search(query: String, japanese: Bool) async throws -> WebSearchResult
}

/// Routing is intentionally local and conservative. It never expands pronouns
/// from private conversation history. This is not a general-purpose PII detector.
public enum WebSearchIntent {
    public static func query(_ input: String) -> String? {
        let text=input.trimmingCharacters(in: .whitespacesAndNewlines), lower=text.lowercased()
        if ["translate ", "翻訳して", "翻訳してください", "英訳して", "という言葉", "を英語", "を日本語"].contains(where: lower.contains) { return nil }
        if ["検索しない", "検索しなく", "調べない", "調べなく", "don't search", "do not search", "don't look up", "do not look up", "no web search", "と言われた", "って言われた"].contains(where: lower.contains) { return nil }
        let japaneseCommand = #"(について|を)?(検索|調べ)して(?:ください|くれる|もらえる|ほしい|欲しい)?[。！？!?]?$"#
        let japaneseLookup = #"(について|を)?調べて(?:ください|くれる|もらえる|ほしい|欲しい)?[。！？!?]?$"#
        let explicit = text.range(of:japaneseCommand,options:.regularExpression) != nil
            || text.range(of:japaneseLookup,options:.regularExpression) != nil
            || lower.range(of: #"^(please |can you |could you )?(search( the web| online)?( for)?|look up|find online)\b"#, options: .regularExpression) != nil
        let topics=["ニュース", "株価", "為替", "価格", "値段", "首相", "大統領", "リリース", "news", "price", "exchange rate", "president", "prime minister", "ceo", "release", "score"]
        let topic=topics.contains(where:lower.contains)
        let current = ["今日", "現在", "最新", "今の", "直近", "today", "current", "latest", "right now", "this week"].contains(where: lower.contains)
        let asking=text.hasSuffix("？") || text.hasSuffix("?") || text.hasSuffix("教えて") || topics.contains(where:text.hasSuffix)
            || lower.range(of:#"^(what|who|how|when|tell me|give me|show me|latest|current)\b"#,options:.regularExpression) != nil
        guard explicit || (topic && current && asking) else { return nil }
        var query=text.replacingOccurrences(of: #"(?i)^(please |can you |could you )?(search( the web| online)?( for)?|look up|find online)\s*"#, with: "", options: .regularExpression)
        query=query.replacingOccurrences(of: #"^(Web|web|ウェブ|ネット)(で|から)"#, with: "", options: .regularExpression)
        query=query.replacingOccurrences(of:japaneseCommand,with:"",options:.regularExpression)
        query=query.replacingOccurrences(of:japaneseLookup,with:"",options:.regularExpression)
        return query.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public static func isSafeQuery(_ query: String) -> Bool {
        let lower=query.lowercased()
        guard (2...240).contains(query.count), query.split(whereSeparator: \.isWhitespace).count<=45,
              !query.contains("\n"), !query.contains("\r"),
              !["それ", "これ", "あれ", "it", "that", "this", "そのこと"].contains(lower),
              !["パスワード", "暗証", "秘密鍵", "住所", "電話番号", "生年月日", "マイナンバーは", "私の", "僕の", "俺の", "password", "secret", "api key", "seed phrase", "my address", "my phone", "my birthday", "my account", "my name", "@", "://"].contains(where: lower.contains),
              lower.range(of: #"\d{7,}|0x[0-9a-f]{16,}"#, options: .regularExpression)==nil,
              !query.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return false }
        return true
    }
}

/// User-owned API key only. No shared key, URL fetch, cloud LLM, or result cache.
public struct BraveWebSearch: WebSearchProviding {
    public typealias Fetch = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    public static let endpoint=URL(string: "https://api.search.brave.com/res/v1/llm/context")!
    private let key: String
    private let fetch: Fetch
    public init(apiKey: String, fetch: @escaping Fetch = { try await WebSearchHTTP.load($0) }) { key=apiKey; self.fetch=fetch }
    public func search(query: String, japanese: Bool) async throws -> WebSearchResult {
        try Task.checkCancellation()
        guard WebSearchIntent.isSafeQuery(query) else { throw WebSearchError.invalidQuery }
        guard Self.validKey(key) else { throw WebSearchError.credentials }
        var request=URLRequest(url: Self.endpoint)
        request.httpMethod="POST"; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(key, forHTTPHeaderField: "X-Subscription-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        var body: [String: Any] = ["q":query, "search_lang":japanese ? "jp":"en", "country":japanese ? "JP":"US",
            "count":5, "maximum_number_of_urls":3, "maximum_number_of_tokens":2048,
            "maximum_number_of_snippets":6, "maximum_number_of_tokens_per_url":512,
            "maximum_number_of_snippets_per_url":2, "safesearch":"strict",
            "enable_local":false, "enable_source_metadata":false, "spellcheck":false]
        // This filters page publication/modification age, not the date of events.
        let lower=query.lowercased()
        if ["今日", "today"].contains(where: lower.contains) { body["freshness"]="pd" }
        else if ["今週", "this week"].contains(where: lower.contains) { body["freshness"]="pw" }
        request.httpBody=try JSONSerialization.data(withJSONObject: body)
        do {
            let (data,response)=try await fetch(request)
            try Task.checkCancellation()
            guard response.url == Self.endpoint else { throw WebSearchError.invalidResponse }
            switch response.statusCode {
            case 200: break
            case 401,403: throw WebSearchError.credentials
            case 429: throw WebSearchError.quota
            default: throw WebSearchError.unavailable
            }
            guard data.count<=128_000 else { throw WebSearchError.invalidResponse }
            let envelope=try JSONDecoder().decode(Envelope.self, from:data)
            var sources: [WebSearchSource]=[], seen=Set<URL>()
            for item in (envelope.grounding.generic ?? []).prefix(50) {
                guard let url=Self.publicURL(item.url), seen.insert(url).inserted else { continue }
                let snippets=(item.snippets ?? []).prefix(2).map { Self.clean($0, limit:850) }.filter { !$0.isEmpty }
                guard !snippets.isEmpty else { continue }
                let title=Self.clean(item.title ?? "", limit:160)
                sources.append(WebSearchSource(title:title.isEmpty ? url.host! : title, url:url, snippets:snippets))
                if sources.count==3 { break }
            }
            return WebSearchResult(query:query, sources:sources)
        } catch is CancellationError { throw CancellationError() }
        catch let error as WebSearchError { throw error }
        catch {
            try Task.checkCancellation()
            // Never forward provider bodies, URLs, request headers, or key material.
            throw WebSearchError.unavailable
        }
    }
    public static func validKey(_ key: String) -> Bool {
        (16...256).contains(key.utf8.count)
            && key.range(of:#"^(0x)?[0-9a-fA-F]{64}$"#,options:.regularExpression)==nil
            && key.unicodeScalars.allSatisfy { (33...126).contains($0.value) }
    }
    public static func publicURL(_ raw: String) -> URL? {
        guard raw.count<=2048, let url=URL(string:raw), url.scheme=="https", url.user==nil, url.password==nil,
              url.port==nil || url.port==443, let host=url.host?.lowercased(), host.contains("."),
              !host.hasSuffix(".local"), !host.hasSuffix(".localhost"), !host.hasSuffix(".internal"),
              host.range(of:#"^[a-z0-9.-]+$"#,options:.regularExpression) != nil,
              !host.allSatisfy({$0.isNumber || $0=="."}) else { return nil }
        return url
    }
    private static func clean(_ raw: String, limit: Int) -> String {
        let stripped=String(raw.prefix(6000)).replacingOccurrences(of:"<[^>]*>", with:"", options:.regularExpression)
        return String(stripped.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) || $0=="\n" }
            .map(String.init).joined().split(whereSeparator: \.isWhitespace).joined(separator:" ").prefix(limit))
    }
    private struct Envelope: Decodable {
        struct Grounding: Decodable {
            struct Item: Decodable { let url:String; let title:String?; let snippets:[String]? }
            let generic:[Item]?
        }
        let grounding:Grounding
    }
}

public enum WebSearchHTTP {
    private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
    }
    public static func load(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard request.url==BraveWebSearch.endpoint, request.httpMethod=="POST" else { throw WebSearchError.invalidQuery }
        let config=URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies=false; config.httpCookieStorage=nil; config.urlCache=nil
        config.timeoutIntervalForRequest=12; config.timeoutIntervalForResource=18
        let session=URLSession(configuration:config, delegate:NoRedirect(), delegateQueue:nil)
        defer { session.invalidateAndCancel() }
        #if canImport(FoundationNetworking)
        let (data,response)=try await session.data(for:request)
        #else
        let (bytes,response)=try await session.bytes(for:request)
        guard response.expectedContentLength<=128_000 else { throw WebSearchError.invalidResponse }
        var data=Data()
        for try await byte in bytes {
            guard data.count<128_000 else { throw WebSearchError.invalidResponse }
            data.append(byte)
        }
        #endif
        try Task.checkCancellation()
        guard data.count<=128_000, let http=response as? HTTPURLResponse else { throw WebSearchError.invalidResponse }
        return (data,http)
    }
}
