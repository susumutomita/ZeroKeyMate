import Combine
import SwiftUI

@MainActor
final class AgeBenchmarkModel: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var reports: [AgeBenchmarkService.Report] = []
    @Published private(set) var message: String?
    private let service = AgeBenchmarkService()
    private var task: Task<Void, Never>?
    func run(_ backend: AgeBenchmarkService.Backend) {
        guard !running else { return }
        running = true; message = nil
        task = Task {
            defer { running = false; task = nil }
            do {
                let result = try await service.run(backend)
                try Task.checkCancellation()
                reports.insert(result, at: 0); reports = Array(reports.prefix(6))
            } catch is CancellationError {} catch {
                message = "This benchmark could not run. Install the matching public benchmark resources and try again."
            }
        }
    }
    func cancel() { task?.cancel() }
}

struct AgeBenchmarkSheet: View {
    @StateObject private var model = AgeBenchmarkModel()
    @State private var backend = AgeBenchmarkService.Backend.whir
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Form {
            Section {
                Text("Compare age proof engines").font(.title2)
                Text("The same age circuit and a fixed synthetic credential. No card scan, personal data, network request or payment.")
                Picker("Proof engine", selection: $backend) {
                    ForEach(AgeBenchmarkService.Backend.allCases) { value in Text(value.rawValue).tag(value) }
                }.disabled(model.running).accessibilityIdentifier("age-benchmark-engine")
                Button("Run benchmark") { model.run(backend) }.disabled(model.running)
                    .accessibilityIdentifier("run-age-benchmark")
                if model.running {
                    ProgressView("Computing on this device…")
                    Button("Discard this run", role: .cancel) { model.cancel() }
                }
                if let message = model.message { Text(L10n.text(message)).foregroundStyle(.secondary) }
            }
            ForEach(model.reports) { report in
                Section(report.backend.rawValue) {
                    LabeledContent("Witness + proof", value: seconds(report.native.timing.witnessAndProofMicroseconds))
                    LabeledContent("Verification", value: seconds(report.native.timing.verificationMicroseconds))
                    LabeledContent("Native total", value: seconds(report.native.timing.totalMicroseconds))
                    LabeledContent("Resource check", value: seconds(report.preparationMicroseconds))
                    LabeledContent("Serialized proof", value: L10n.format("%lld bytes", report.native.serializedProofBytes))
                    Label("Modified order rejected", systemImage: "checkmark.shield")
                    Text(report.operatingSystem + " · " + report.device).font(.caption)
                    Text(L10n.format("Thermal state: %lld → %lld", report.thermalBefore, report.thermalAfter)).font(.caption)
                    ShareLink("Share timing report", item: json(report))
                }.accessibilityIdentifier("age-benchmark-result")
            }
            Section {
                Text("Native total includes key loading, witness creation, proving, verification and serialization. Resource hashing and the modified-order check are separate. File caches are not controlled; repeat runs before comparing.")
                Text("WHIR is experimental here. Purchases still use the verified Groth16 path. Wrapped WHIR is unavailable because the upstream recursive verifier is not compatible with this proof format.")
                Text("Proof sizes use the native ProveKit file format, not EVM calldata. This benchmark does not establish zero-knowledge privacy, production security or on-chain compatibility.")
            }.font(.footnote).foregroundStyle(.secondary)
        }
        .navigationTitle("Age proof benchmark").navigationBarTitleDisplayMode(.inline)
        .onDisappear { model.cancel() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.cancel() } }
    }
    private func seconds(_ microseconds: UInt64) -> String { String(format: "%.3f s", Double(microseconds) / 1_000_000) }
    private func json(_ report: AgeBenchmarkService.Report) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(report)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}
