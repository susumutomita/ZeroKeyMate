import Foundation

#if canImport(DockKit) && !targetEnvironment(simulator)
import DockKit

/// All DockKit writes are called by MateModel's single reconciliation task.
/// Docking alone does not authorize camera capture.
@MainActor
final class DockService {
    private var observationTask: Task<Void, Never>?
    private var accessory: DockAccessory?
    private var trackingTask:Task<Void,Never>?
    var onTrackingSubjects:((Int)->Void)?
    private(set) var trackingButtonEnabled = false

    var isConnected: Bool { accessory != nil }

    func observe(onChange: @escaping @MainActor (String?) -> Void) {
        guard observationTask == nil else { return }
        observationTask = Task { [weak self] in
            do {
                let changes = try DockAccessoryManager.shared.accessoryStateChanges
                for await change in changes {
                    guard !Task.isCancelled, let self else { return }
                    if change.state == .docked, let accessory = change.accessory {
                        if self.accessory != accessory {
                            self.trackingTask?.cancel()
                            self.trackingTask=Task{[weak self] in
                                do {
                                    for await state in try accessory.trackingStates {
                                        guard let self,!Task.isCancelled,self.accessory == accessory else{return}
                                        self.onTrackingSubjects?(state.trackedSubjects.count)
                                    }
                                }catch{onChange("DockKit: \(error.localizedDescription)")}
                            }
                        }
                        self.accessory = accessory
                        self.trackingButtonEnabled = change.trackingButtonEnabled
                    } else {
                        self.trackingTask?.cancel();self.trackingTask=nil;self.onTrackingSubjects?(0)
                        self.accessory = nil
                        self.trackingButtonEnabled = false
                    }
                    onChange(nil)
                }
            } catch {
                self?.accessory = nil
                self?.trackingButtonEnabled = false
                onChange("DockKit: \(error.localizedDescription)")
            }
            self?.observationTask = nil
        }
    }

    func setTrackingEnabled(_ enabled: Bool) async throws {
        try await DockAccessoryManager.shared.setSystemTrackingEnabled(enabled)
    }

    deinit {
        observationTask?.cancel();trackingTask?.cancel()
    }
}
#else
/// DockKit is absent from the simulator SDK. Report that limitation explicitly;
/// this adapter must never report a connection or fake an enabled motor.
@MainActor
final class DockService {
    var onTrackingSubjects:((Int)->Void)?
    let isConnected = false
    let trackingButtonEnabled = false

    func observe(onChange: @escaping @MainActor (String?) -> Void) {
        onChange("DockKit is unavailable in this environment. Test the stand on a physical iPhone.")
    }

    func setTrackingEnabled(_ enabled: Bool) async throws {
        guard !enabled else { throw DockUnavailable.unsupported }
        // Disabling absent hardware is a no-op; enabling is never a success.
    }
}

private enum DockUnavailable: LocalizedError {
    case unsupported

    var errorDescription: String? {
        "DockKit is unavailable in this environment."
    }
}
#endif
