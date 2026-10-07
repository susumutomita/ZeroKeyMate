import Foundation
import MateCore

/// Offline synthetic acceptance using the application's real runtime adapter
/// and index. This runner does not download models or read app/user data.
@main struct LocalEmbeddingQA {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {throw LocalSearchFailure.invalidInput}
        let source=URL(fileURLWithPath:CommandLine.arguments[1])
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        let model=LocalEmbeddingModel.embeddingGemma2,files=LocalModelFiles(directory:directory)
        let verified=try await files.install(model,download:{_,destination,_,_ in
            try FileManager.default.copyItem(at:source,to:destination)
        },progress:{_ in})
        let runtime=LocalEmbeddingRuntime(),index=LocalSemanticIndex()
        do {
            try await runtime.initialize(file:verified,availableMemory:0)
            throw LocalSearchFailure.invalidVector
        } catch LocalSearchFailure.memory {print("PASS low-memory guard before model load")}
        await runtime.close();await runtime.close()
        try await runtime.initialize(file:verified)
        let corpus:[LocalSearchDocument]=[
            .init(id:"bike",text:"自転車は庭の物置に置いています。"),
            .init(id:"drink",text:"My favorite drink is green tea."),
            .init(id:"space",text:"The Moon orbits Earth.")]
        for (query,expected) in [("Where is the bicycle stored?","bike"),("自転車をどこに置いた？","bike"),
                                  ("好きな飲み物は何？","drink"),("What is my favorite beverage?","drink")] {
            let start=Date()
            let hits=try await index.search(query:query,documents:corpus,model:model,embed:{try await runtime.embed($0)})
            guard hits.first?.id == expected else {throw LocalSearchFailure.invalidVector}
            print("PASS \(query) → \(expected); \(Int(Date().timeIntervalSince(start)*1_000)) ms")
        }
        await index.reset()
        let empty=try await index.search(query:"bicycle",documents:[],model:model,embed:{try await runtime.embed($0)})
        guard empty.isEmpty else {throw LocalSearchFailure.invalidVector}
        await runtime.close()
        print("PASS offline real-model retrieval and deletion; synthetic fixtures only")
    }
}
