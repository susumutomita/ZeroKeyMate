import SwiftUI
import MateCore

struct LocalMemorySearchSettingsView:View {
    @ObservedObject var model:CompanionModel
    @ObservedObject var search:LocalMemorySearch
    var body:some View {
        if LocalEmbeddingRuntime.isSupported {settings}
        else {
            Form {
                Section {
                    Text("EmbeddingGemma 2 is unavailable in this build.").accessibilityIdentifier("local-model-unavailable")
                    Text("This build does not include the local embedding runtime. Conversation and existing search remain available.")
                }
            }.navigationTitle("Local memory search").navigationBarTitleDisplayMode(.inline)
        }
    }
    private var settings:some View {
        Form {
            Section("Embedding model") {
                Picker("Embedding model",selection:Binding(get:{search.selection},set:{search.select($0)})) {
                    Text("Off").tag(LocalSearchSelection.off)
                    Text(verbatim:"EmbeddingGemma 2 · Text 270M").tag(LocalSearchSelection.embeddingGemma2)
                }.disabled(search.busy).accessibilityIdentifier("local-embedding-model")
                Text("Search local notes and completed messages on this iPhone. Conversation replies continue to use Apple Intelligence.").font(.footnote)
                status
                if search.selection == .embeddingGemma2 {
                    if search.busy {
                        Button("Cancel"){search.stop()}.accessibilityIdentifier("cancel-local-model")
                    } else if search.state != .ready {
                        Button("Download and prepare model (165 MB)"){search.download()}
                            .accessibilityIdentifier("download-local-model")
                        Button("Check downloaded model"){search.restore()}
                    }
                }
                Button("Disable and delete model",role:.destructive){search.deleteModel()}
                    .disabled(search.busy).accessibilityIdentifier("delete-local-model")
            }
            Section {
                NavigationLink("Search local memory") {LocalMemorySearchView(model:model,search:search)}
                    .disabled(search.state != .ready).accessibilityIdentifier("open-local-memory-search")
                Text("Search results are excerpts, not verified facts. Only the sources you select are indexed. Recent completed user messages are limited to the current conversation; notes are limited to the text visible in Settings. Older text may be omitted to fit memory limits.").font(.footnote)
            }
            Section("Before downloading") {
                Text("Downloading contacts Hugging Face and its file hosts, which can see your IP address. Queries, notes and conversations are never sent to them. Once installed, search works offline.")
                Text("This is an early preview. The download is about 165 MB; preparing it uses additional storage for a model cache. At least 4 GB of device memory is required. Indexes stay in memory and are cleared when sources change, when you leave search, or when the app enters the background. Clearing conversation removes its searchable messages. Clear and save notes separately to remove notes.")
                Text("Model and runtime: Apache 2.0. No model weights are bundled. Search never approves payments, proves identity or signs requests.")
                Link("Model details and license",destination:URL(string:"https://huggingface.co/litert-community/embeddinggemma-2-text-270m-litert-lm/tree/9be6e8b90982095dc05c2bd162e4b954ee4dbac7")!)
            }.font(.footnote)
        }.navigationTitle("Local memory search").navigationBarTitleDisplayMode(.inline)
            .task {search.restore()}
            .onDisappear {search.invalidateCorpus()}
    }
    @ViewBuilder private var status:some View {
        switch search.state {
        case .unavailable:Text("EmbeddingGemma 2 is unavailable in this build.")
        case .off:Text("Off").accessibilityIdentifier("local-model-status")
        case .missing:Text("Not downloaded or prepared").accessibilityIdentifier("local-model-status")
        case .checking:ProgressView("Verifying and preparing model")
        case .downloading:ProgressView(value:search.progress) {Text("Downloading model")}
        case .ready:Text("Ready on this iPhone").accessibilityIdentifier("local-model-status")
        case .failed(let message):Text(L10n.text(message)).accessibilityIdentifier("local-model-status")
        }
    }
}

struct LocalMemorySearchView:View {
    @ObservedObject var model:CompanionModel
    @ObservedObject var search:LocalMemorySearch
    @State private var query=""
    @State private var includeConversation=true
    @State private var includeNotes=false
    @FocusState private var editing:Bool
    private var corpus:[LocalSearchDocument] {
        LocalMemoryCorpus.documents(messages:model.messages,notes:model.localNotes,
            includeConversation:includeConversation,includeNotes:includeNotes)
    }
    var body:some View {
        Form {
            Section("Local sources") {
                Toggle("Completed user messages",isOn:$includeConversation)
                Toggle("Local notes",isOn:$includeNotes)
                Text("Assistant replies and web results are excluded. Selecting notes includes only your current notes. Results never leave this iPhone or enter an action flow.").font(.footnote)
            }
            Section {
                TextField("Search query",text:$query).focused($editing).submitLabel(.search)
                    .onSubmit {run()}.accessibilityIdentifier("local-search-query")
                Button("Search on this iPhone"){run()}
                    .disabled(search.state != .ready || search.searching || query.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || query.utf8.count>1_000 || corpus.isEmpty)
                    .accessibilityIdentifier("run-local-search")
                if search.searching {
                    ProgressView("Searching local memory")
                    Button("Cancel"){search.invalidateCorpus()}.accessibilityIdentifier("cancel-local-search")
                }
                if corpus.isEmpty {Text("No completed messages or selected notes to search.").font(.footnote)}
                if search.state != .ready {Text("Local search is unavailable. Return to model settings to prepare it.").font(.footnote)}
                if let status=search.searchStatus {Text(L10n.text(status)).font(.footnote)}
            }
            ForEach(search.hits) {hit in
                Section(L10n.text(hit.id.hasPrefix("notes:") ? "Local notes":"Your completed message")) {
                    Text(verbatim:hit.document.text).textSelection(.enabled)
                        .accessibilityIdentifier("local-search-excerpt")
                }
            }
        }.navigationTitle("Search local memory").navigationBarTitleDisplayMode(.inline)
            .onChange(of:query){_,_ in search.invalidateCorpus()}
            .onChange(of:includeConversation){_,_ in search.invalidateCorpus()}
            .onChange(of:includeNotes){_,_ in search.invalidateCorpus()}
            .onDisappear {query="";search.stop()}
    }
    private func run() {editing=false;search.search(query:query,documents:corpus)}
}
