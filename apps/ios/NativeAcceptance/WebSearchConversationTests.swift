import XCTest
import MateCore
@testable import ZeroKeyMate

private actor SearchStub:WebSearchProviding {
    var calls:[String]=[]
    let failure:WebSearchError?
    let empty:Bool
    init(failure:WebSearchError?=nil,empty:Bool=false){self.failure=failure;self.empty=empty}
    func search(query:String,japanese:Bool) async throws -> WebSearchResult {
        calls.append(query)
        if let failure {throw failure}
        return WebSearchResult(query:query,sources:empty ? []:[.init(title:"Example space agency",url:URL(string:"https://example.org/news")!,snippets:["The launch is scheduled for Friday."])])
    }
}
private struct MissingSummary:SearchSummarizing {
    func summarize(_ result:WebSearchResult,japanese:Bool) async throws -> String? {nil}
}
private struct GroundedSummary:SearchSummarizing {
    func summarize(_ result:WebSearchResult,japanese:Bool) async throws -> String? {
        LocalSearchSummary.validated(answer:japanese ? "発表によると打ち上げは金曜日です。":"The announcement schedules the launch for Friday.",source:0,snippet:0,result:result)
    }
}
final class WebSearchConversationTests:XCTestCase {
    func testConversationUsesSearchWithoutPrivateHistoryOrPaidAction() async throws {
        let stub=SearchStub()
        let live=ConversationService(search:stub,searchSummary:GroundedSummary())
        let answer=try await live.reply(to:"最新の宇宙ニュースを調べて",history:[.init(isUser:true,text:"My private meeting")],observations:"private camera observation",notes:"private notes",replyLanguage:"日本語")
        XCTAssertTrue(answer.text.contains("金曜日"))
        XCTAssertTrue(answer.text.contains("[1]"))
        XCTAssertEqual(answer.webSearch?.sources.first?.url.host,"example.org")
        XCTAssertNil(answer.service);XCTAssertTrue(answer.disclosure.isEmpty)
        let calls=await stub.calls;XCTAssertEqual(calls,["最新の宇宙ニュース"])
    }
    func testDisabledFailureAndNoResultsDoNotReachFreeFormModel() async throws {
        for failure in [WebSearchError.disabled,.credentials,.quota,.unavailable] {
            let service=ConversationService(search:SearchStub(failure:failure),searchSummary:GroundedSummary())
            let reply=try await service.reply(to:"Search for current space news",history:[],observations:"",notes:"",replyLanguage:"English")
            XCTAssertNil(reply.webSearch);XCTAssertNil(reply.service)
            XCTAssertFalse(reply.text.contains("Friday"))
        }
        let web=WebSearchConversation(provider:SearchStub(empty:true),summarizer:GroundedSummary())
        let result=try await web.reply(to:"今日のニュースは？",japanese:true)
        XCTAssertTrue(result?.text.contains("見つかりません") == true)
        XCTAssertTrue(result?.result?.sources.isEmpty == true)
    }
    func testUnavailableLocalSummaryUsesLabelledExcerpt() async throws {
        let web=WebSearchConversation(provider:SearchStub(),summarizer:MissingSummary())
        let reply=try await web.reply(to:"Search for space news",japanese:false)
        XCTAssertTrue(reply?.text.contains("excerpt") == true)
        XCTAssertTrue(reply?.text.contains("The launch is scheduled for Friday.") == true)
    }
    func testUnrelatedAndPrivateMessagesNeverCallSearch() async throws {
        let stub=SearchStub()
        let conversation=WebSearchConversation(provider:stub,summarizer:MissingSummary())
        let chat=try await conversation.reply(to:"今日の会議は長かった",japanese:true)
        XCTAssertNil(chat)
        let privateQuery=try await conversation.reply(to:"私の暗証番号は1234を検索して",japanese:true)
        XCTAssertNil(privateQuery?.result)
        let calls=await stub.calls;XCTAssertTrue(calls.isEmpty)
    }
    func testInventedEvidenceAndURLsAreRejected() {
        let result=WebSearchResult(query:"space news",sources:[.init(title:"Agency",url:URL(string:"https://example.org")!,snippets:["The launch is scheduled for Friday."])])
        XCTAssertNil(LocalSearchSummary.validated(answer:"A claim",source:9,snippet:0,result:result))
        XCTAssertNil(LocalSearchSummary.validated(answer:"A claim",source:0,snippet:99,result:result))
        XCTAssertNil(LocalSearchSummary.validated(answer:"https://attacker.invalid",source:0,snippet:0,result:result))
    }
}

private actor SearchHistoryConversation:ConversationResponding {
    var histories:[[ConversationTurn]]=[]
    func availability()->String? {nil}
    func reply(to text:String,history:[ConversationTurn],observations:String,notes:String,replyLanguage:String) async throws -> ConversationReply {
        histories.append(history)
        if histories.count==1 {
            let result=WebSearchResult(query:"space news",sources:[.init(title:"Example",url:URL(string:"https://example.org")!,snippets:["untrusted retrieved content"])])
            return ConversationReply(text:"untrusted retrieved summary",service:nil,disclosure:"",webSearch:result)
        }
        return ConversationReply(text:"Hello",service:nil,disclosure:"")
    }
}
private actor SearchPlannerSpy:AgentPlanning {
    var inputs:[String]=[]
    func request(from input:String) async throws -> AgentRequest? {inputs.append(input);return nil}
}
@MainActor final class CompanionSearchTests:XCTestCase {
    func testSearchSkipsPaidPlannerAndDoesNotSeedPrivateModelHistory() async throws {
        let conversation=SearchHistoryConversation(),planner=SearchPlannerSpy()
        let model=CompanionModel(conversation:conversation,planner:planner)
        model.readAloud=false
        defer {model.rest()}
        model.send("Search for space news")
        try await finished(model)
        let planned=await planner.inputs
        XCTAssertTrue(planned.isEmpty)
        XCTAssertNotNil(model.messages.last?.webSearch)
        model.send("Hello")
        try await finished(model)
        let histories=await conversation.histories
        XCTAssertEqual(histories.count,2)
        XCTAssertFalse(histories.last!.contains(where:{$0.text.contains("untrusted")}))
        model.clearConversation()
        XCTAssertTrue(model.messages.isEmpty)
    }
    private func finished(_ model:CompanionModel) async throws {
        for _ in 0..<100 {
            if !model.thinking {return}
            try await Task.sleep(for:.milliseconds(20))
        }
        XCTFail("Conversation failed to finish")
    }
}
