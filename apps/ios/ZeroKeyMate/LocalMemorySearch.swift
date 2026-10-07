import Combine
import Foundation
import MateCore

@MainActor
final class LocalMemorySearch:ObservableObject {
    enum State:Equatable {case unavailable,off,missing,checking,downloading,ready,failed(String)}
    @Published private(set) var selection:LocalSearchSelection
    @Published private(set) var state:State = .off
    @Published private(set) var progress=0.0
    @Published private(set) var searching=false
    @Published private(set) var hits:[LocalSearchHit]=[]
    @Published private(set) var searchStatus:String?
    private let defaults:UserDefaults
    private let files:LocalModelFiles
    private let transfer:LocalModelFiles.Download
    private let runtime=LocalEmbeddingRuntime()
    private let index=LocalSemanticIndex()
    private var operation:Task<Void,Never>?
    private var cleanup:Task<Void,Never>?
    private var searchTask:Task<Void,Never>?
    private var generation:UInt64=0
    private var searchGeneration:UInt64=0
    private let model=LocalEmbeddingModel.embeddingGemma2
    init(defaults:UserDefaults = .standard,directory:URL?=nil,
         transfer:@escaping LocalModelFiles.Download={url,destination,size,progress in
             try await LocalWeightTransfer.download(url,to:destination,expectedBytes:size,progress:progress)
         }) {
        self.defaults=defaults
        self.transfer=transfer
        selection=LocalEmbeddingRuntime.isSupported ? LocalSearchSelection(savedValue:defaults.string(forKey:LocalSearchSelection.preferenceKey)):.off
        let root=directory ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("LocalEmbeddingModels",isDirectory:true)
        files=LocalModelFiles(directory:root)
        if !LocalEmbeddingRuntime.isSupported {state = .unavailable}
    }
    var busy:Bool {state == .checking || state == .downloading}
    func select(_ value:LocalSearchSelection) {
        guard LocalEmbeddingRuntime.isSupported else {state = .unavailable;return}
        stop();selection=value;defaults.set(value.rawValue,forKey:LocalSearchSelection.preferenceKey)
        restore()
    }
    /// Settings persistence is not evidence that weights or native inference are ready.
    func restore() {
        guard LocalEmbeddingRuntime.isSupported else {state = .unavailable;return}
        guard !busy else {return}
        guard selection == .embeddingGemma2 else {state = .off;return}
        generation &+= 1;let current=generation
        let waiting=cleanup
        state = .checking
        operation=Task { [self] in
            do {
                await waiting?.value
                try Task.checkCancellation()
                guard current == generation else {return}
                try await files.discardInterruptedDownloads()
                let file=try await files.verifiedFile(for:model)
                try Task.checkCancellation()
                guard current == generation else {return}
                guard let file else {state = .missing;return}
                try await runtime.initialize(file:file)
                try Task.checkCancellation()
                guard current == generation else {return}
                state = .ready
            } catch {
                guard current == generation,!Task.isCancelled else {return}
                state = .failed(Self.message(error))
            }
        }
    }
    func download() {
        guard LocalEmbeddingRuntime.isSupported,selection == .embeddingGemma2,!busy else {return}
        generation &+= 1;let current=generation
        let waiting=cleanup
        progress=0;state = .downloading
        operation=Task { [self] in
            do {
                await waiting?.value
                try Task.checkCancellation()
                guard current == generation else {return}
                let file=try await files.install(model,download:transfer,progress:{[weak self] value in
                    Task { @MainActor in
                        guard let self,self.generation == current else {return}
                        self.progress=value
                    }
                })
                try Task.checkCancellation()
                guard current == generation else {return}
                state = .checking
                try await runtime.initialize(file:file)
                try Task.checkCancellation()
                guard current == generation else {return}
                progress=1;state = .ready
            } catch {
                guard current == generation,!Task.isCancelled else {return}
                state = .failed(Self.message(error))
            }
        }
    }
    func stop() {
        let pending=operation,previousCleanup=cleanup
        generation &+= 1;operation?.cancel();operation=nil
        invalidateCorpus()
        state = !LocalEmbeddingRuntime.isSupported ? .unavailable : selection == .off ? .off:.missing
        // Snapshot dependencies before publishing the new cleanup task. A
        // retry waits for the previous transfer and engine close, so it cannot
        // race partial-file cleanup or close a newly prepared engine.
        cleanup=Task { [runtime] in
            await pending?.value
            await previousCleanup?.value
            await runtime.close()
        }
    }
    func deleteModel() {
        guard LocalEmbeddingRuntime.isSupported else {state = .unavailable;return}
        select(.off)
        let waiting=cleanup
        let current=generation;state = .checking
        operation=Task {
            await waiting?.value
            guard current == generation,!Task.isCancelled else {return}
            do {try await files.remove(model);state = .off}
            catch {state = .failed("The model could not be deleted. Unlock your iPhone and retry.")}
        }
    }
    func memoryWarning() {
        stop()
        if LocalEmbeddingRuntime.isSupported,selection != .off {state = .failed("Memory is limited. Close other apps, then retry local search.")}
    }
    func invalidateCorpus() {
        searchGeneration &+= 1;searchTask?.cancel();searchTask=nil
        hits=[];searching=false;searchStatus=nil
        guard LocalEmbeddingRuntime.isSupported else {return}
        Task {await index.reset()}
    }
    func search(query:String,documents:[LocalSearchDocument]) {
        guard state == .ready,!searching else {return}
        searchGeneration &+= 1;let current=searchGeneration
        searching=true;hits=[];searchStatus=nil
        searchTask=Task {
            do {
                let found=try await index.search(query:query,documents:documents,model:model,
                    embed:{[runtime] text in try await runtime.embed(text)})
                try Task.checkCancellation()
                guard current == searchGeneration else {return}
                hits=found;searching=false
                if found.isEmpty {searchStatus="No matching text in the selected local sources."}
            } catch {
                guard current == searchGeneration,!Task.isCancelled else {return}
                searching=false;searchStatus=Self.message(error)
            }
        }
    }
    static func message(_ error:Error)->String {
        switch error as? LocalSearchFailure {
        case .integrity:return "The model file failed verification. Delete it and download again."
        case .memory:return "This preview requires an iPhone with at least 4 GB of memory."
        case .invalidInput:return "Use a short query and the bounded local sources."
        default:return "Local search is unavailable. Retry when the model and device are ready."
        }
    }
}

/// Only completed, visible user messages and explicitly selected notes. Never
/// reads assistant messages, provider results, card/wallet state or hidden stores.
enum LocalMemoryCorpus {
    static func documents(messages:[ConversationMessage],notes:String,includeConversation:Bool,includeNotes:Bool)->[LocalSearchDocument] {
        var documents:[LocalSearchDocument]=[]
        if includeNotes {append(notes,id:"notes",to:&documents)}
        if includeConversation {
            for (position,message) in messages.enumerated().reversed() where message.isUser {
                guard position+1<messages.count,!messages[position+1].isUser else {continue}
                append(message.text,id:message.id.uuidString,to:&documents)
            }
        }
        return documents
    }
    private static func append(_ text:String,id:String,to documents:inout [LocalSearchDocument]) {
        // Bounded chunks preserve literal text and UTF-8 character boundaries.
        var chunk="",part=0
        for character in text {
            if chunk.utf8.count+String(character).utf8.count>LocalSemanticIndex.maximumDocumentBytes {
                guard add(chunk,id:"\(id):\(part)",to:&documents) else {return}
                part+=1;chunk=""
            }
            guard String(character).utf8.count<=LocalSemanticIndex.maximumDocumentBytes else {continue}
            chunk.append(character)
        }
        _ = add(chunk,id:"\(id):\(part)",to:&documents)
    }
    private static func add(_ text:String,id:String,to documents:inout [LocalSearchDocument])->Bool {
        guard !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {return true}
        guard documents.count<LocalSemanticIndex.maximumDocuments,
              documents.reduce(0,{$0+$1.text.utf8.count})+text.utf8.count<=LocalSemanticIndex.maximumCorpusBytes else {return false}
        documents.append(.init(id:id,text:text));return true
    }
}
