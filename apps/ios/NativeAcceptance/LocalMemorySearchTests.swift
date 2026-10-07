import XCTest
import MateCore
@testable import ZeroKeyMate

final class LocalMemorySearchTests:XCTestCase {
    func testCorpusIncludesOnlyExplicitSourcesAndCompletedUserMessages() {
        let messages:[ConversationMessage]=[
            .init(isUser:false,text:"Assistant-only fact"),
            .init(isUser:true,text:"Interrupted"),
            .init(isUser:true,text:"I keep a bicycle in the garden."),
            .init(isUser:false,text:"Retrieved web content"),
            .init(isUser:true,text:"Unanswered")]
        let user=LocalMemoryCorpus.documents(messages:messages,notes:"tea",includeConversation:true,includeNotes:false)
        XCTAssertEqual(user.map(\.text),["I keep a bicycle in the garden."])
        let notes=LocalMemoryCorpus.documents(messages:messages,notes:"tea",includeConversation:false,includeNotes:true)
        XCTAssertEqual(notes.map(\.text),["tea"])
        XCTAssertTrue(LocalMemoryCorpus.documents(messages:messages,notes:"tea",includeConversation:false,includeNotes:false).isEmpty)
        XCTAssertTrue(LocalMemoryCorpus.documents(messages:[],notes:"",includeConversation:true,includeNotes:true).isEmpty)
    }
    func testJapaneseChunksRespectBytesAndBoundTheCorpus() {
        let text=String(repeating:"自転車を庭に置いています。",count:100)
        let chunks=LocalMemoryCorpus.documents(messages:[],notes:text,includeConversation:false,includeNotes:true)
        XCTAssertEqual(chunks.map(\.text).joined(),text)
        XCTAssertTrue(chunks.allSatisfy{$0.text.utf8.count<=LocalSemanticIndex.maximumDocumentBytes})
        let bounded=LocalMemoryCorpus.documents(messages:[],notes:String(repeating:text,count:100),includeConversation:false,includeNotes:true)
        XCTAssertLessThanOrEqual(bounded.count,32)
        XCTAssertLessThanOrEqual(bounded.reduce(0,{$0+$1.text.utf8.count}),24_000)
    }
    func testDownloadRedirectPolicyRejectsOtherHostsAndCredentials() {
        for url in ["https://huggingface.co/model","https://cas-bridge.xethub.hf.co/file"] {
            XCTAssertTrue(LocalWeightTransfer.permitted(URL(string:url)!))
        }
        for url in ["http://huggingface.co/model","https://huggingface.co.example.org/file","https://localhost/model","https://user:secret@huggingface.co/model","https://huggingface.co:8080/model"] {
            XCTAssertFalse(LocalWeightTransfer.permitted(URL(string:url)!))
        }
    }
    func testLowMemoryFailsBeforeOpeningModelAndRuntimeCloseIsIdempotent() async throws {
        let runtime=LocalEmbeddingRuntime()
        do {try await runtime.initialize(file:URL(fileURLWithPath:"/synthetic-not-a-model"),availableMemory:0);XCTFail("Memory guard")}
        catch {XCTAssertEqual(error as? LocalSearchFailure,LocalEmbeddingRuntime.isSupported ? .memory:.unavailable)}
        await runtime.close();await runtime.close()
    }
    /// Optional, real inference acceptance. Stage the pinned public weights into
    /// this test bundle locally; absent weights skip honestly, never use a stub.
    func testRealOfflineEnglishJapaneseRetrieval() async throws {
        guard LocalEmbeddingRuntime.isSupported else {throw XCTSkip("This build does not include the embedding runtime.")}
        guard let file=Bundle(for:Self.self).url(forResource:"EmbeddingQA",withExtension:"litertlm") else {
            throw XCTSkip("Stage the verified public model as NativeAcceptance/EmbeddingQA.litertlm to run real inference.")
        }
        let runtime=LocalEmbeddingRuntime(),index=LocalSemanticIndex()
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        let files=LocalModelFiles(directory:directory),model=LocalEmbeddingModel.embeddingGemma2
        let verified=try await files.install(model,download:{_,destination,_,_ in
            try FileManager.default.copyItem(at:file,to:destination)
        },progress:{_ in})
        try await runtime.initialize(file:verified)
        let corpus:[LocalSearchDocument]=[
            .init(id:"bike",text:"自転車は庭の物置に置いています。"),
            .init(id:"drink",text:"My favorite drink is green tea."),
            .init(id:"space",text:"The Moon orbits Earth.")]
        for (query,expected) in [("Where is the bicycle stored?","bike"),("自転車をどこに置いた？","bike"),
                                  ("好きな飲み物は何？","drink"),("What is my favorite beverage?","drink")] {
            let hits=try await index.search(query:query,documents:corpus,model:model,
                embed:{try await runtime.embed($0)})
            XCTAssertEqual(hits.first?.id,expected,query)
        }
        await index.reset()
        let removed=try await index.search(query:"bicycle",documents:[],model:model,embed:{try await runtime.embed($0)})
        XCTAssertTrue(removed.isEmpty)
        await runtime.close()
    }
    @MainActor func testOffIsDefaultAndMemoryWarningClearsResultsWithoutEnablingCloud() {
        let name=UUID().uuidString,defaults=UserDefaults(suiteName:name)!
        defer {defaults.removePersistentDomain(forName:name)}
        let search=LocalMemorySearch(defaults:defaults,directory:FileManager.default.temporaryDirectory.appendingPathComponent(name))
        XCTAssertEqual(search.selection,.off)
        search.memoryWarning()
        XCTAssertEqual(search.state,LocalEmbeddingRuntime.isSupported ? .off:.unavailable)
        XCTAssertTrue(search.hits.isEmpty)
        XCTAssertFalse(search.searching)
    }
    @MainActor func testSavedSelectionDoesNotMakeMissingWeightsAvailable() async {
        let name=UUID().uuidString,defaults=UserDefaults(suiteName:name)!
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(name)
        defer {defaults.removePersistentDomain(forName:name);try? FileManager.default.removeItem(at:directory)}
        let search=LocalMemorySearch(defaults:defaults,directory:directory)
        if !LocalEmbeddingRuntime.isSupported {
            search.select(.embeddingGemma2)
            XCTAssertEqual(search.state,.unavailable)
            XCTAssertEqual(search.selection,.off)
            XCTAssertNil(defaults.string(forKey:LocalSearchSelection.preferenceKey))
            return
        }
        search.select(.embeddingGemma2)
        for _ in 0..<1_000 where search.busy {await Task.yield()}
        XCTAssertEqual(search.state,.missing)
        XCTAssertEqual(defaults.string(forKey:LocalSearchSelection.preferenceKey),"embeddingGemma2")
        let restored=LocalMemorySearch(defaults:defaults,directory:directory)
        XCTAssertEqual(restored.selection,.embeddingGemma2)
        XCTAssertNotEqual(restored.state,.ready)
        restored.select(.off)
        XCTAssertEqual(defaults.string(forKey:LocalSearchSelection.preferenceKey),"off")
        XCTAssertEqual(restored.state,.off)
    }
    @MainActor func testRealModelImmediateRetryWaitsForCancelledTransferAndOfflineRestore() async throws {
        guard LocalEmbeddingRuntime.isSupported,
              let fixture=Bundle(for:Self.self).url(forResource:"EmbeddingQA",withExtension:"litertlm") else {
            throw XCTSkip("Stage the pinned public EmbeddingQA.litertlm for real coordinator acceptance.")
        }
        let name=UUID().uuidString,defaults=UserDefaults(suiteName:name)!
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(name)
        defer {defaults.removePersistentDomain(forName:name);try? FileManager.default.removeItem(at:directory)}
        let gate=FirstTransferGate()
        let search=LocalMemorySearch(defaults:defaults,directory:directory,transfer:{_,destination,_,progress in
            await gate.begin()
            // The first transfer finishes late after cancellation. Real pinned
            // bytes still pass through production integrity and readiness checks.
            try FileManager.default.copyItem(at:fixture,to:destination)
            progress(1)
        })
        search.select(.embeddingGemma2)
        try await waitUntil {search.state == .missing}
        search.download()
        try await waitUntil {await gate.calls == 1}
        search.stop();search.download()
        await gate.release()
        try await waitUntil {search.state == .ready}
        let count=await gate.calls
        XCTAssertEqual(count,2)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil).contains{$0.pathExtension == "partial"})
        search.select(.off);search.select(.embeddingGemma2)
        try await waitUntil {search.state == .ready}
        let corpus:[LocalSearchDocument]=[.init(id:"bike",text:"自転車は庭の物置に置いています。")]
        search.search(query:"Where is the bicycle stored?",documents:corpus)
        try await waitUntil {!search.searching}
        XCTAssertEqual(search.hits.first?.id,"bike")
        search.invalidateCorpus()
        XCTAssertTrue(search.hits.isEmpty)
        search.deleteModel()
        try await waitUntil {search.state == .off}
        XCTAssertEqual(search.selection,.off)
        let remaining=try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil).map(\.lastPathComponent)
        XCTAssertTrue(remaining.isEmpty,"Model files remain: \(remaining)")
    }
    @MainActor private func waitUntil(_ condition:() async -> Bool) async throws {
        let clock=ContinuousClock(),deadline=clock.now.advanced(by:.seconds(30))
        while !(await condition()),clock.now<deadline {try await Task.sleep(for:.milliseconds(20))}
        let passed=await condition()
        XCTAssertTrue(passed,"Coordinator did not reach its expected state.")
    }
}

private actor FirstTransferGate {
    private(set) var calls=0
    private var continuation:CheckedContinuation<Void,Never>?
    func begin() async {
        calls+=1
        if calls == 1 {await withCheckedContinuation {continuation=$0}}
    }
    func release() {continuation?.resume();continuation=nil}
}
