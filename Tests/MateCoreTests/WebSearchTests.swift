import XCTest
@testable import MateCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class WebSearchTests:XCTestCase {
    private let sample=Data(#"{"grounding":{"generic":[{"url":"https://example.org/news","title":"News","snippets":["The launch is scheduled for Friday."]}]}}"#.utf8)
    func testMinimalPOSTHasNoHistoryOrLocationAndReturnsSources() async throws {
        let payload=sample
        let api=BraveWebSearch(apiKey:"test-key-never-real",fetch:{request in
            XCTAssertEqual(request.url,BraveWebSearch.endpoint)
            XCTAssertNil(request.url?.query)
            XCTAssertEqual(request.httpMethod,"POST")
            XCTAssertEqual(request.value(forHTTPHeaderField:"X-Subscription-Token"),"test-key-never-real")
            XCTAssertNil(request.value(forHTTPHeaderField:"x-loc-lat"))
            let body=try XCTUnwrap(JSONSerialization.jsonObject(with:request.httpBody!) as? [String:Any])
            XCTAssertEqual(body["q"] as? String,"今日の宇宙ニュース")
            XCTAssertEqual(body["freshness"] as? String,"pd")
            XCTAssertEqual(body["search_lang"] as? String,"jp")
            XCTAssertEqual(body["enable_local"] as? Bool,false)
            XCTAssertNil(body["history"]);XCTAssertNil(body["notes"])
            return (payload,HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!)
        })
        let result=try await api.search(query:"今日の宇宙ニュース",japanese:true)
        XCTAssertEqual(result.sources.first?.title,"News")
        XCTAssertEqual(result.sources.first?.snippets,["The launch is scheduled for Friday."])
        XCTAssertEqual(result.query,"今日の宇宙ニュース")
    }
    func testProviderFailuresRemainTypedAndNeverExposeResponseBody() async throws {
        for (code,expected) in [(401,WebSearchError.credentials),(403,.credentials),(429,.quota),(302,.unavailable),(500,.unavailable)] {
            let api=BraveWebSearch(apiKey:"test-key-never-real",fetch:{request in
                (Data("sensitive provider diagnostics".utf8),HTTPURLResponse(url:request.url!,statusCode:code,httpVersion:nil,headerFields:nil)!)
            })
            do {_ = try await api.search(query:"space news",japanese:false);XCTFail("Expected failure")}
            catch {XCTAssertEqual(error as? WebSearchError,expected)}
        }
    }
    func testNoResultsInvalidResponseAndOversizeAreNotAnswers() async throws {
        let empty=BraveWebSearch(apiKey:"test-key-never-real",fetch:{request in
            (Data(#"{"grounding":{}}"#.utf8),HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!)
        })
        let result=try await empty.search(query:"space news",japanese:false)
        XCTAssertTrue(result.sources.isEmpty)
        for payload in [Data("{}".utf8),Data(repeating:32,count:128_001)] {
            let api=BraveWebSearch(apiKey:"test-key-never-real",fetch:{request in
                (payload,HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!)
            })
            do {_ = try await api.search(query:"space news",japanese:false);XCTFail("Expected failure")}
            catch {XCTAssertNotNil(error as? WebSearchError)}
        }
    }
    func testRedirectDestinationRejectedEvenWithValidJSON() async throws {
        let payload=sample
        let api=BraveWebSearch(apiKey:"test-key-never-real",fetch:{_ in
            (payload,HTTPURLResponse(url:URL(string:"https://example.org/")!,statusCode:200,httpVersion:nil,headerFields:nil)!)
        })
        do {_ = try await api.search(query:"space news",japanese:false);XCTFail("Expected failure")}
        catch {XCTAssertEqual(error as? WebSearchError,.invalidResponse)}
    }
    func testSourceURLsAndUnboundedSnippetsAreFiltered() async throws {
        for raw in ["http://example.org", "https://localhost", "https://127.0.0.1", "https://10.0.0.1", "https://host.local", "https://user:pass@example.org", "https://[::1]", "javascript:alert(1)","https://example.org:8080"] {
            XCTAssertNil(BraveWebSearch.publicURL(raw),raw)
        }
        let items=(0..<7).map {index in ["url":"https://example.org/\(index)","title":"<b>Title</b>","snippets":[String(repeating:"x",count:2000),"second","third"]] as [String:Any]}
        let data=try JSONSerialization.data(withJSONObject:["grounding":["generic":items]])
        let api=BraveWebSearch(apiKey:"test-key-never-real",fetch:{request in
            (data,HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!)
        })
        let result=try await api.search(query:"space news",japanese:false)
        XCTAssertEqual(result.sources.count,3)
        XCTAssertEqual(result.sources[0].title,"Title")
        XCTAssertEqual(result.sources[0].snippets.count,2)
        XCTAssertEqual(result.sources[0].snippets[0].count,850)
    }
    func testBilingualSearchRoutingDoesNotUploadOrdinaryConversation() {
        for (input,expected) in [("最新の宇宙ニュースを調べて","最新の宇宙ニュース"),("Search for the latest space news","the latest space news"),("今日のニュースは？","今日のニュースは？"),("What is the current exchange rate?","What is the current exchange rate?")] {
            XCTAssertEqual(WebSearchIntent.query(input),expected)
        }
        XCTAssertEqual(WebSearchIntent.query("翻訳APIの公式仕様を調べて"),"翻訳APIの公式仕様")
        for input in ["今日は疲れた", "I had a long meeting today", "今日何を買った？", "Buy a beer", "Translate 'latest news'", "今日のニュースを英語に翻訳して"] {
            XCTAssertNil(WebSearchIntent.query(input),input)
        }
        for query in ["それ", "it", "私の暗証番号は1234", "my password is test", "https://example.org/?secret=x", "私の住所からお店", "email alice@example.org",String(repeating:"a",count:241)] {
            XCTAssertFalse(WebSearchIntent.isSafeQuery(query),query)
        }
        XCTAssertTrue(WebSearchIntent.isSafeQuery("マイナンバーカードの公式仕様"))
    }
    func testCommonWalletSecretsCannotBeSavedAsSearchKeys() {
        XCTAssertFalse(BraveWebSearch.validKey("0x"+String(repeating:"a",count:64)))
        XCTAssertFalse(BraveWebSearch.validKey(String(repeating:"b",count:64)))
        XCTAssertFalse(BraveWebSearch.validKey("word word word word word word word word word word word word"))
        XCTAssertTrue(BraveWebSearch.validKey("test-key-never-real"))
    }
    func testCancellationAndRejectedQueriesNeverBecomeResults() async throws {
        let api=BraveWebSearch(apiKey:"test-key-never-real",fetch:{_ in throw CancellationError()})
        do {_ = try await api.search(query:"space news",japanese:false);XCTFail("Expected cancellation")}
        catch {XCTAssertTrue(error is CancellationError)}
        let noNetwork=BraveWebSearch(apiKey:"test-key-never-real",fetch:{_ in XCTFail("Must not send private query");throw CancellationError()})
        do {_ = try await noNetwork.search(query:"my password is test",japanese:false);XCTFail("Expected rejection")}
        catch {XCTAssertEqual(error as? WebSearchError,.invalidQuery)}
    }
}
