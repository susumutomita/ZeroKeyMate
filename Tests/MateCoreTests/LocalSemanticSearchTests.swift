import XCTest
import CryptoSwift
@testable import MateCore

private actor EmbeddingCalls {
    var count=0
    func embed(_ text:String)->[Float] {count+=1;return text.contains("bicycle") ? [0,1]:[1,0]}
}
private actor EmbeddingGate {
    var entered=false
    var continuation:CheckedContinuation<[Float],Never>?
    func embed(_ text:String) async -> [Float] {
        entered=true
        return await withCheckedContinuation {continuation=$0}
    }
    func release() {continuation?.resume(returning:[1,0]);continuation=nil}
}

final class LocalSemanticSearchTests:XCTestCase {
    private func model(_ data:Data=Data("abc".utf8),revision:String="test-v1",dimensions:Int=2)->LocalEmbeddingModel {
        .init(revision:revision,sha256:Array(data).sha256().toHexString(),byteCount:Int64(data.count),dimensions:dimensions,
            downloadURL:URL(string:"https://huggingface.co/synthetic-fixture")!)
    }
    private func directory()->URL {FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)}
    func testDefaultAndUnknownPreferencesStayOffAndArtifactIsPinned() {
        XCTAssertEqual(LocalSearchSelection(savedValue:nil),.off)
        XCTAssertEqual(LocalSearchSelection(savedValue:"unknown-model"),.off)
        XCTAssertEqual(LocalSearchSelection(savedValue:"embeddingGemma2"),.embeddingGemma2)
        let model=LocalEmbeddingModel.embeddingGemma2
        XCTAssertTrue(model.downloadURL.path.contains(model.revision))
        XCTAssertFalse(model.downloadURL.path.contains("/main/"))
        XCTAssertEqual(model.byteCount,164_626_432)
        XCTAssertEqual(model.dimensions,128)
        XCTAssertEqual(model.sha256,"2d079ee2f6f066b1f368e8d7c819f55214eaef1d0513b312321901f30ab286fb")
    }
    func testVerifiedInstallIsPersistentAndUsableOfflineWithoutAnotherTransfer() async throws {
        let directory=directory();defer {try? FileManager.default.removeItem(at:directory)}
        let files=LocalModelFiles(directory:directory),spec=model()
        let url=try await files.install(spec,download:{url,destination,size,progress in
            XCTAssertEqual(url,spec.downloadURL);XCTAssertEqual(size,3)
            try Data("abc".utf8).write(to:destination);progress(0.9)
        },progress:{_ in})
        let restored=LocalModelFiles(directory:directory)
        let verified=try await restored.verifiedFile(for:spec)
        XCTAssertEqual(verified,url)
        _ = try await restored.install(spec,download:{_,_,_,_ in XCTFail("Offline cache must not download")},progress:{_ in})
        for timestamp in [1,2] {
            let name=url.lastPathComponent + "_\(timestamp)_3.text_encoder.xnnpack_cache"
            try Data("public-weight-cache-fixture".utf8).write(to:directory.appendingPathComponent(name))
        }
        let unrelated=directory.appendingPathComponent("other-model.litertlm_1_3.text_encoder.xnnpack_cache")
        try Data("unrelated-fixture".utf8).write(to:unrelated)
        try await restored.remove(spec)
        let deleted=try await restored.verifiedFile(for:spec)
        XCTAssertNil(deleted)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:directory.path),[unrelated.lastPathComponent])
    }
    func testCorruptionWrongLengthAndInterruptedTransferNeverBecomeReady() async throws {
        for content in ["abd","ab","abcd"] {
            let directory=directory();defer {try? FileManager.default.removeItem(at:directory)}
            let files=LocalModelFiles(directory:directory),spec=model()
            do {
                _ = try await files.install(spec,download:{_,destination,_,_ in try Data(content.utf8).write(to:destination)},progress:{_ in})
                XCTFail("Corrupt content must fail")
            } catch {XCTAssertEqual(error as? LocalSearchFailure,.integrity)}
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:directory.path).isEmpty)
        }
        let directory=directory();defer {try? FileManager.default.removeItem(at:directory)}
        let files=LocalModelFiles(directory:directory),spec=model()
        do {
            _ = try await files.install(spec,download:{_,destination,_,_ in
                try Data("a".utf8).write(to:destination);throw LocalSearchFailure.download
            },progress:{_ in})
            XCTFail("Interrupted transfer must fail")
        } catch {XCTAssertEqual(error as? LocalSearchFailure,.download)}
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:directory.path).isEmpty)
        try Data("ab".utf8).write(to:directory.appendingPathComponent("abandoned.partial"))
        try await files.discardInterruptedDownloads()
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:directory.path).isEmpty)
    }
    func testCancelledDownloadCleansPartialAndCannotPublishCompleteWeights() async throws {
        let directory=directory();defer {try? FileManager.default.removeItem(at:directory)}
        let files=LocalModelFiles(directory:directory),spec=model(),gate=EmbeddingGate()
        let work=Task {
            try await files.install(spec,download:{_,destination,_,_ in
                try Data("abc".utf8).write(to:destination)
                _ = await gate.embed("")
            },progress:{_ in})
        }
        while !(await gate.entered) {await Task.yield()}
        work.cancel();await gate.release()
        do {_ = try await work.value;XCTFail("Cancellation must survive")}
        catch {XCTAssertTrue(error is CancellationError)}
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:directory.path).isEmpty)
    }
    func testCacheRebuildsForDeletionRevisionAndDimensionsAndUsesTaskPrefixes() async throws {
        let index=LocalSemanticIndex(),calls=EmbeddingCalls()
        let corpus=[LocalSearchDocument(id:"one",text:"green tea"),.init(id:"two",text:"bicycle")]
        let embed:LocalSemanticIndex.Embed={text in
            XCTAssertTrue(text.hasPrefix("task: search result | text: ") || text.hasPrefix("task: search query | text: "))
            return await calls.embed(text)
        }
        let hits=try await index.search(query:" bicycle ",documents:corpus,model:model(),embed:embed)
        XCTAssertEqual(hits.map(\.id),["two"])
        _ = try await index.search(query:"tea",documents:corpus,model:model(),embed:embed)
        var count=await calls.count;XCTAssertEqual(count,4)
        let afterDelete=try await index.search(query:"bicycle",documents:[corpus[0]],model:model(),embed:embed)
        XCTAssertTrue(afterDelete.isEmpty)
        count=await calls.count;XCTAssertEqual(count,6)
        _ = try await index.search(query:"tea",documents:[corpus[0]],model:model(revision:"test-v2"),embed:embed)
        count=await calls.count;XCTAssertEqual(count,8)
        do {
            _ = try await index.search(query:"tea",documents:[corpus[0]],model:model(dimensions:3),embed:embed)
            XCTFail("Dimension mismatch must fail")
        } catch {XCTAssertEqual(error as? LocalSearchFailure,.invalidVector)}
    }
    func testResetDuringNativeWorkAndTaskCancellationDiscardResults() async throws {
        for cancel in [false,true] {
            let index=LocalSemanticIndex(),gate=EmbeddingGate(),spec=model()
            let work=Task {try await index.search(query:"tea",documents:[.init(id:"one",text:"tea")],model:spec,embed:{await gate.embed($0)})}
            while !(await gate.entered) {await Task.yield()}
            if cancel {work.cancel()} else {await index.reset()}
            await gate.release()
            do {_ = try await work.value;XCTFail("Stale result must not survive")}
            catch {XCTAssertTrue(error is CancellationError)}
            let fresh=try await index.search(query:"tea",documents:[],model:spec,embed:{_ in XCTFail("Empty corpus");return []})
            XCTAssertTrue(fresh.isEmpty)
        }
    }
    func testBoundsAndInvalidVectorsFailWithoutUnboundedAllocation() async throws {
        let index=LocalSemanticIndex(),spec=model()
        for corpus in [Array(repeating:LocalSearchDocument(id:"one",text:"tea"),count:33),
                       [.init(id:"one",text:String(repeating:"あ",count:401))]] {
            do {
                _ = try await index.search(query:"tea",documents:corpus,model:spec,embed:{_ in XCTFail("Bounds must fail before embedding");return []})
                XCTFail("Oversized corpus")
            } catch {XCTAssertEqual(error as? LocalSearchFailure,.invalidInput)}
        }
        for vector:[Float] in [[.nan,1],[0,0],[1]] {
            do {_ = try await index.search(query:"tea",documents:[.init(id:"one",text:"tea")],model:spec,embed:{_ in vector});XCTFail("Invalid vector")}
            catch {XCTAssertEqual(error as? LocalSearchFailure,.invalidVector)}
        }
    }
}
