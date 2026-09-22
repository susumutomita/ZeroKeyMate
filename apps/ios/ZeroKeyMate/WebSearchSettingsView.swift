import SwiftUI
import MateCore

struct WebSearchSettingsView:View {
    @State private var key=""
    @State private var enabled=false
    @State private var busy=false
    @State private var status:String?
    @FocusState private var editing:Bool
    var body:some View {
        Form {
            Section {
                LabeledContent("Web search",value:L10n.text(enabled ? "Enabled":"Off"))
                    .accessibilityIdentifier("search-enabled-status")
                Text("Ask ‘Search for the latest space news.’ Mate searches with Brave, then answers on your iPhone with source links.")
                    .font(.footnote)
            }
            Section("Your Brave API key") {
                SecureField("Paste your API key",text:$key)
                    .textContentType(nil).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($editing).submitLabel(.done).onSubmit {editing=false}
                    .accessibilityIdentifier("search-api-key")
                Button("Save and enable search") {
                    editing=false;busy=true;status=nil
                    let value=key.trimmingCharacters(in:.whitespacesAndNewlines)
                    Task {
                        do {
                            try await WebSearchAccess.shared.save(key:value)
                            key="";enabled=true;status="Search enabled. No test request was sent."
                        } catch {status="Couldn't save the key. Unlock your iPhone and try again."}
                        busy=false
                    }
                }.disabled(!BraveWebSearch.validKey(key.trimmingCharacters(in:.whitespacesAndNewlines)) || busy)
                    .accessibilityIdentifier("save-search-key")
                    Button("Disable search and delete key",role:.destructive) {
                        editing=false;busy=true;status=nil
                        Task {
                            do {try await WebSearchAccess.shared.disable();enabled=false;key="";status="Search disabled and key deleted."}
                            catch {enabled=false;status="Search is off, but the key could not be deleted. Unlock your iPhone and retry."}
                            busy=false
                        }
                    }.disabled(busy).accessibilityIdentifier("delete-search-key")
                if let status {Text(L10n.text(status)).font(.footnote).accessibilityIdentifier("search-settings-status")}
            }
            Section("Before enabling") {
                Text("Search sends the current search query and language to Brave. Your IP address is visible to Brave. Mate does not attach conversation history, notes, camera data, card information or GPS. Do not put private information in search questions.")
                Text("Mate also searches supported current-information questions, such as today's news. Search is off until you enable it. Search results stay in memory; clearing the conversation removes them.")
                Text("The key is stored only in this iPhone's Keychain. Never enter a wallet key. Your Brave account's pricing and data terms apply. Mate limits attempts to 20 per UTC day on this installation; this is not an account billing cap.")
                Link("Brave API account and pricing",destination:URL(string:"https://brave.com/search/api/")!)
                Link("Brave Search API dashboard",destination:URL(string:"https://api-dashboard.search.brave.com/")!)
            }.font(.footnote)
        }
        .navigationTitle("Web search").navigationBarTitleDisplayMode(.inline)
        .toolbar {ToolbarItemGroup(placement:.keyboard) {Spacer();Button("Done"){editing=false}}}
        .task {enabled=await WebSearchAccess.shared.enabled()}
        .onDisappear {key=""}
    }
}

struct WebSearchSourcesView:View {
    let result:WebSearchResult
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            Text("Web search · Brave").font(.caption).foregroundStyle(.secondary)
            Text(verbatim:result.query).font(.caption).foregroundStyle(.secondary)
            HStack(spacing:4) {Text("Retrieved");Text(result.fetchedAt,style:.date);Text(result.fetchedAt,style:.time)}
                .font(.caption2).foregroundStyle(.secondary)
            ForEach(Array(result.sources.enumerated()),id:\.element.id) {index,source in
                Link(destination:source.url) {
                    Text(verbatim:"[\(index+1)] \(source.title)").lineLimit(2)
                }.font(.footnote).accessibilityIdentifier("web-source-\(index+1)")
            }
        }.accessibilityIdentifier("web-search-sources")
    }
}
