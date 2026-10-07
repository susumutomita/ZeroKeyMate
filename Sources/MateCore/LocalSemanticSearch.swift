import Foundation
import CryptoSwift
#if canImport(CryptoKit)
import CryptoKit
#endif

public enum LocalSearchFailure: Error, Sendable, Equatable {
    case unavailable, busy, invalidInput, invalidVector, integrity, download, memory
}

/// Weights are downloaded only by an explicit user action. No private text is
/// part of this URL, and no embedding service is exposed by this module.
public struct LocalEmbeddingModel: Sendable, Equatable {
    public let revision: String
    public let sha256: String
    public let byteCount: Int64
    public let dimensions: Int
    public let downloadURL: URL
    public var indexIdentity: String { "\(revision):\(sha256):LiteRT-LM-0.18.0:search-v1:\(dimensions)" }
    public static let embeddingGemma2 = LocalEmbeddingModel(
        revision: "9be6e8b90982095dc05c2bd162e4b954ee4dbac7",
        sha256: "2d079ee2f6f066b1f368e8d7c819f55214eaef1d0513b312321901f30ab286fb",
        byteCount: 164_626_432, dimensions: 128,
        downloadURL: URL(string: "https://huggingface.co/litert-community/embeddinggemma-2-text-270m-litert-lm/resolve/9be6e8b90982095dc05c2bd162e4b954ee4dbac7/embeddinggemma-2-text-270m.litertlm")!)
    public init(revision: String, sha256: String, byteCount: Int64, dimensions: Int, downloadURL: URL) {
        self.revision=revision; self.sha256=sha256; self.byteCount=byteCount
        self.dimensions=dimensions; self.downloadURL=downloadURL
    }
}

public enum LocalSearchSelection: String, Sendable, CaseIterable {
    case off, embeddingGemma2
    public static let preferenceKey = "local-embedding-model-v1"
    public init(savedValue: String?) { self = savedValue.flatMap(Self.init(rawValue:)) ?? .off }
}

/// Install atomically after bounded, streaming verification. An interrupted
/// transfer is never published as an installed model. Partial files are not resumed.
public actor LocalModelFiles {
    public typealias Download = @Sendable (URL, URL, Int64, @escaping @Sendable (Double) -> Void) async throws -> Void
    private let directory: URL
    private var installing=false
    public init(directory: URL) { self.directory=directory }
    public func file(for model: LocalEmbeddingModel) -> URL {
        directory.appendingPathComponent(model.sha256 + ".litertlm")
    }
    public func verifiedFile(for model: LocalEmbeddingModel) throws -> URL? {
        let url=file(for:model)
        guard FileManager.default.fileExists(atPath:url.path) else { return nil }
        try Self.verify(url,model:model)
        return url
    }
    public func install(_ model: LocalEmbeddingModel, download: Download,
                        progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard !installing else { throw LocalSearchFailure.busy }
        installing=true
        let partial=directory.appendingPathComponent(UUID().uuidString + ".partial")
        defer { installing=false; try? FileManager.default.removeItem(at:partial) }
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        var values=URLResourceValues(); values.isExcludedFromBackup=true
        var folder=directory; try folder.setResourceValues(values)
        if let existing=try? verifiedFile(for:model) { return existing }
        try await download(model.downloadURL,partial,model.byteCount,progress)
        try Task.checkCancellation()
        try Self.verify(partial,model:model)
        try Task.checkCancellation()
        let destination=file(for:model)
        try? FileManager.default.removeItem(at:destination)
        try FileManager.default.moveItem(at:partial,to:destination)
        return destination
    }
    public func remove(_ model: LocalEmbeddingModel) throws {
        let url=file(for:model)
        if FileManager.default.fileExists(atPath:url.path) { try FileManager.default.removeItem(at:url) }
    }
    public func discardInterruptedDownloads() throws {
        guard !installing, FileManager.default.fileExists(atPath:directory.path) else { return }
        for url in try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil)
            where url.pathExtension == "partial" { try FileManager.default.removeItem(at:url) }
    }
    private static func verify(_ url: URL, model: LocalEmbeddingModel) throws {
        let size=try FileManager.default.attributesOfItem(atPath:url.path)[.size] as? NSNumber
        guard size?.int64Value == model.byteCount else { throw LocalSearchFailure.integrity }
        let input=try FileHandle(forReadingFrom:url); defer { try? input.close() }
        #if canImport(CryptoKit)
        var hash=CryptoKit.SHA256()
        #else
        var hash=SHA2(variant:.sha256)
        #endif
        while let chunk=try input.read(upToCount:65_536), !chunk.isEmpty {
            try Task.checkCancellation()
            #if canImport(CryptoKit)
            hash.update(data:chunk)
            #else
            _ = try hash.update(withBytes:Array(chunk))
            #endif
        }
        #if canImport(CryptoKit)
        let digest=Array(hash.finalize()).toHexString()
        #else
        let digest=try hash.finish().toHexString()
        #endif
        guard digest == model.sha256 else { throw LocalSearchFailure.integrity }
    }
}

public struct LocalSearchDocument: Sendable, Equatable, Identifiable {
    public let id: String
    public let text: String
    public init(id: String, text: String) { self.id=id; self.text=text }
}
public struct LocalSearchHit: Sendable, Equatable, Identifiable {
    public let document: LocalSearchDocument
    public let score: Float
    public var id: String { document.id }
}

/// In-memory, bounded retrieval only. The caller supplies the explicitly allowed
/// corpus. Results are original text, never action authority or generated facts.
public actor LocalSemanticIndex {
    public typealias Embed = @Sendable (String) async throws -> [Float]
    public static let maximumDocuments=32
    public static let maximumDocumentBytes=1_200
    public static let maximumCorpusBytes=24_000
    private var identity=""
    private var documents:[LocalSearchDocument]=[]
    private var vectors:[[Float]]=[]
    private var generation:UInt64=0
    private var busy=false
    public init() {}
    public func reset() { generation &+= 1; identity=""; documents=[]; vectors=[] }
    public func search(query: String, documents corpus: [LocalSearchDocument], model: LocalEmbeddingModel,
                       embed: Embed) async throws -> [LocalSearchHit] {
        guard !busy else { throw LocalSearchFailure.busy }
        let query=query.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !query.isEmpty,query.utf8.count<=1_000,model.dimensions>0,model.dimensions<=1_024,
              corpus.count<=Self.maximumDocuments,Set(corpus.map(\.id)).count == corpus.count,
              corpus.allSatisfy({ !$0.text.isEmpty && $0.text.utf8.count<=Self.maximumDocumentBytes }),
              corpus.reduce(0,{ $0+$1.text.utf8.count })<=Self.maximumCorpusBytes else { throw LocalSearchFailure.invalidInput }
        busy=true; defer { busy=false }
        try Task.checkCancellation()
        if identity != model.indexIdentity || documents != corpus {
            reset()
            let revision=generation
            var next:[[Float]]=[]
            for document in corpus {
                let vector=try await embed("task: search result | text: " + document.text.trimmingCharacters(in:.whitespacesAndNewlines))
                try check(revision)
                next.append(try normalized(vector,dimensions:model.dimensions))
            }
            try check(revision)
            identity=model.indexIdentity; documents=corpus; vectors=next
        }
        guard !documents.isEmpty else { return [] }
        let revision=generation
        let vector=try await embed("task: search query | text: " + query)
        try check(revision)
        let normalizedQuery=try normalized(vector,dimensions:model.dimensions)
        return zip(documents,vectors).map { document,vector in
            LocalSearchHit(document:document,score:zip(vector,normalizedQuery).reduce(0) { $0+$1.0*$1.1 })
        }.filter { $0.score>=0.25 }.sorted { $0.score == $1.score ? $0.id<$1.id : $0.score>$1.score }.prefix(5).map { $0 }
    }
    private func check(_ revision: UInt64) throws {
        try Task.checkCancellation()
        guard generation == revision else { throw CancellationError() }
    }
    private func normalized(_ vector: [Float], dimensions: Int) throws -> [Float] {
        guard vector.count == dimensions,vector.allSatisfy(\.isFinite) else { throw LocalSearchFailure.invalidVector }
        let length=sqrt(vector.reduce(Double(0)) { $0+Double($1)*Double($1) })
        guard length.isFinite,length>0 else { throw LocalSearchFailure.invalidVector }
        return vector.map { Float(Double($0)/length) }
    }
}
