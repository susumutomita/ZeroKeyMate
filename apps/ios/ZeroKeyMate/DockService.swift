import DockKit

/// All DockKit writes are called by MateModel's single reconciliation task.
/// Docking alone does not authorize camera capture.
@MainActor
final class DockService {
    private var observationTask: Task<Void, Never>?
    private var accessory: DockAccessory?
    private(set) var trackingButtonEnabled = false

    var isConnected: Bool { accessory != nil }

    func observe(onChange: @escaping @MainActor (String?) -> Void) {
        guard observationTask == nil else { return }
        #if targetEnvironment(simulator)
        onChange("Simulator：DockKitは実機で確認してください。")
        #else
        observationTask = Task { [weak self] in
            do {
                let changes = try DockAccessoryManager.shared.accessoryStateChanges
                for await change in changes {
                    guard !Task.isCancelled, let self else { return }
                    if change.state == .docked, let accessory = change.accessory {
                        self.accessory = accessory
                        self.trackingButtonEnabled = change.trackingButtonEnabled
                    } else {
                        self.accessory = nil
                        self.trackingButtonEnabled = false
                    }
                    onChange(nil)
                }
            } catch {
                self?.accessory = nil
                self?.trackingButtonEnabled = false
                onChange("DockKit：\(error.localizedDescription)")
            }
            self?.observationTask = nil
        }
        #endif
    }

    func setTrackingEnabled(_ enabled: Bool) async throws {
        #if !targetEnvironment(simulator)
        try await DockAccessoryManager.shared.setSystemTrackingEnabled(enabled)
        #endif
    }

    deinit {
        observationTask?.cancel()
    }
}
