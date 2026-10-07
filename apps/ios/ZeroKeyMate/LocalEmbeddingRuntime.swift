import Foundation
import MateCore
#if canImport(LiteRTLM)
import LiteRTLM

/// Serial native work; no tools, network clients, or financial adapters.
actor LocalEmbeddingRuntime {
    nonisolated static let isSupported=true
    private var engine:EmbeddingEngine?
    private var loading=false
    private var revision:UInt64=0
    func initialize(file:URL,availableMemory:UInt64=UInt64(ProcessInfo.processInfo.physicalMemory)) async throws {
        guard engine == nil else {return}
        guard !loading else {throw LocalSearchFailure.busy}
        // Conservative eligibility guard, supplemented by iOS memory warnings.
        guard availableMemory>=4_000_000_000 else {throw LocalSearchFailure.memory}
        loading=true;defer {loading=false}
        let current=revision
        let fresh=EmbeddingEngine(config:.init(modelPath:file.path,backend:.cpu(threadCount:2),
            maxInputLength:512))
        do {
            try await fresh.initialize()
            try Task.checkCancellation()
            guard current == revision else {throw CancellationError()}
            let probe=try await fresh.computeEmbedding(contents:[.text("task: search query | text: readiness")],
                options:.init(normalize:true,outputSize:LocalEmbeddingModel.embeddingGemma2.dimensions))
            try Task.checkCancellation()
            guard current == revision else {throw CancellationError()}
            guard probe.embedding.count == LocalEmbeddingModel.embeddingGemma2.dimensions,
                  probe.embedding.allSatisfy(\.isFinite),probe.embedding.contains(where:{$0 != 0}) else {throw LocalSearchFailure.invalidVector}
            engine=fresh
        } catch {await fresh.close();throw error}
    }
    func embed(_ text:String) async throws -> [Float] {
        try Task.checkCancellation()
        guard let engine else {throw LocalSearchFailure.unavailable}
        let result=try await engine.computeEmbedding(contents:[.text(text)],
            options:.init(normalize:true,outputSize:LocalEmbeddingModel.embeddingGemma2.dimensions))
        try Task.checkCancellation()
        return result.embedding
    }
    func close() async {
        revision &+= 1
        let old=engine;engine=nil
        await old?.close()
    }
}
#else
/// Source-only consumers without the native SDK never claim readiness.
actor LocalEmbeddingRuntime {
    nonisolated static let isSupported=false
    func initialize(file:URL,availableMemory:UInt64=UInt64(ProcessInfo.processInfo.physicalMemory)) throws {
        throw LocalSearchFailure.unavailable
    }
    func embed(_ text:String) throws -> [Float] {throw LocalSearchFailure.unavailable}
    func close() {}
}
#endif
