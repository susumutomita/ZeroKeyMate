import AVFoundation
import Combine
import MateCore

@MainActor
final class MateModel: ObservableObject {
    enum CameraPhase: String {
        case off = "カメラ OFF"
        case starting = "カメラ起動中"
        case on = "カメラ ON・端末内"
        case stopping = "カメラ停止中"
    }

    @Published private(set) var cameraPhase: CameraPhase = .off
    @Published private(set) var dockConnected = false
    @Published private(set) var trackingEnabled: Bool?
    @Published private(set) var message: String?
    @Published private(set) var dockMessage: String?
    @Published private(set) var captureRequested = false

    private let camera = CameraService()
    private let dock = DockService()
    private var intent = CaptureIntent()
    private var cameraRunning = false
    private var lastTrackingRequest: Bool?
    private var lastTrackingButtonEnabled = false
    private var revision: UInt64 = 0
    private var reconciliationTask: Task<Void, Never>?
    private var notifications = Set<AnyCancellable>()

    var isTransitioning: Bool { cameraPhase == .starting || cameraPhase == .stopping }

    init() {
        dock.observe { [weak self] error in
            guard let self else { return }
            let wasConnected = self.dockConnected
            if wasConnected != self.dock.isConnected
                || self.lastTrackingButtonEnabled != self.dock.trackingButtonEnabled {
                self.lastTrackingRequest = nil
            }
            self.lastTrackingButtonEnabled = self.dock.trackingButtonEnabled
            self.dockConnected = self.dock.isConnected
            self.dockMessage = error
            if wasConnected && !self.dockConnected {
                // Physically removing the phone stops capture. Re-docking does not resume it.
                self.intent.requestStop()
            }
            self.scheduleReconciliation()
        }

        // An interruption never silently resumes capture. Require another user action.
        for name in [AVCaptureSession.wasInterruptedNotification, AVCaptureSession.runtimeErrorNotification] {
            NotificationCenter.default.publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard let self, self.cameraRunning || self.isTransitioning else { return }
                    self.message = "カメラが中断されました。再開には開始ボタンを押してください。"
                    self.intent.requestStop()
                    self.scheduleReconciliation()
                }
                .store(in: &notifications)
        }
    }

    func setForeground(_ foreground: Bool) {
        if intent.isForeground != foreground { lastTrackingRequest = nil }
        intent.setForeground(foreground)
        scheduleReconciliation()
    }

    func startCapture() {
        guard !isTransitioning else { return }
        message = nil
        intent.requestStart()
        scheduleReconciliation()
    }

    func stopCapture() {
        // This remains available while permission or camera startup is pending.
        intent.requestStop()
        scheduleReconciliation()
    }

    private func scheduleReconciliation() {
        revision &+= 1
        captureRequested = intent.shouldCapture
        guard reconciliationTask == nil else { return }
        reconciliationTask = Task { [weak self] in
            guard let self else { return }
            await self.reconcile()
            self.reconciliationTask = nil
        }
    }

    private func reconcile() async {
        // Only this task mutates capture and tracking hardware. New UI/lifecycle
        // events advance revision; a late permission grant cannot bypass Stop.
        var processedRevision: UInt64
        repeat {
            processedRevision = revision
            if intent.shouldCapture && !cameraRunning {
                cameraPhase = .starting
                let allowed = await CameraService.requestPermission()
                guard intent.shouldCapture else {
                    cameraPhase = .off
                    continue
                }
                if !allowed {
                    message = "カメラへのアクセスが許可されていません。iPhoneの設定で変更できます。"
                    intent.requestStop()
                    captureRequested = false
                    cameraPhase = .off
                } else {
                    do {
                        try await camera.start()
                        cameraRunning = true
                        cameraPhase = intent.shouldCapture ? .on : .stopping
                    } catch {
                        await camera.stop()
                        cameraRunning = false
                        cameraPhase = .off
                        intent.requestStop()
                        captureRequested = false
                        message = error.localizedDescription
                    }
                }
            }

            if !intent.shouldCapture && cameraRunning {
                cameraPhase = .stopping
                // Stop the sensor before awaiting a potentially slow accessory operation.
                await camera.stop()
                cameraRunning = false
                cameraPhase = .off
            }

            let wantsTracking = cameraRunning && intent.shouldCapture
                && dock.isConnected && dock.trackingButtonEnabled
            if lastTrackingRequest != wantsTracking {
                // Avoid a feedback loop when DockKit emits another state event.
                lastTrackingRequest = wantsTracking
                do {
                    try await dock.setTrackingEnabled(wantsTracking)
                    trackingEnabled = wantsTracking
                } catch {
                    // A failed request means unknown, not a confirmed OFF state.
                    trackingEnabled = nil
                    dockMessage = "追尾設定を確認できません：\(error.localizedDescription)"
                }
            }
        } while processedRevision != revision
    }
}
