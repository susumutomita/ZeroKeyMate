import AVFoundation
import Combine
import Foundation
import MateCore

@MainActor
final class MateModel:ObservableObject {
    enum CameraPhase:String {
        case off="Camera OFF",starting="Camera starting",on="Camera ON · On-device",stopping="Camera stopping"
    }
    @Published private(set) var cameraPhase:CameraPhase = .off
    @Published private(set) var dockConnected=false
    @Published private(set) var trackingEnabled:Bool?
    @Published private(set) var message:String?
    @Published private(set) var dockMessage:String?
    @Published private(set) var captureRequested=false
    @Published private(set) var horizontalFocus=0.0
    @Published private(set) var verticalFocus=0.0
    @Published private(set) var detectedFaces=0
    @Published private(set) var dockTrackingSubjects=0
    @Published private(set) var dockTrackingButtonEnabled=false
    private var trackingRetryAt=Date.distantPast
    var onDetach:(()->Void)?
    var onInterruption:(()->Void)?
    private var observation:FrameObservation?
    private var gaze=CompanionGaze()
    private let camera=CameraService()
    private let dock=DockService()
    private var intent=CaptureIntent()
    private var cameraRunning=false
    private var lastTrackingRequest:Bool?
    private var lastTrackingButtonEnabled=false
    private var revision:UInt64=0
    private var reconciliationTask:Task<Void,Never>?
    private var notifications=Set<AnyCancellable>()
    var isTransitioning:Bool {cameraPhase == .starting || cameraPhase == .stopping}
    var currentObservation:String {
        guard cameraRunning,intent.shouldCapture,let observation,
              Date().timeIntervalSince(observation.capturedAt)<3 else {return "No current camera observations. Do not claim to see."}
        return observation.description
    }
    init() {
        Task{[weak self] in
            guard let self else{return}
            await self.camera.setObserver{[weak self] value in
                Task{@MainActor [weak self] in
                    guard let self,self.intent.shouldCapture,self.cameraRunning else{return}
                    self.observation=value
                    self.detectedFaces=value.faceCount
                    let position=self.gaze.update(x:value.horizontalFocus,y:value.verticalFocus,
                                                  now:ProcessInfo.processInfo.systemUptime)
                    self.horizontalFocus=position.x
                    self.verticalFocus=position.y
                    if self.lastTrackingRequest == nil,Date()>=self.trackingRetryAt {self.scheduleReconciliation()}
                }
            }
        }
        dock.onTrackingSubjects={[weak self] count in self?.dockTrackingSubjects=count}
        dock.observe{[weak self] error in
            guard let self else{return}
            let wasConnected=self.dockConnected
            if wasConnected != self.dock.isConnected || self.lastTrackingButtonEnabled != self.dock.trackingButtonEnabled {
                self.lastTrackingRequest=nil
            }
            self.lastTrackingButtonEnabled=self.dock.trackingButtonEnabled
            self.dockTrackingButtonEnabled=self.dock.trackingButtonEnabled
            self.dockConnected=self.dock.isConnected;self.dockMessage=error
            if wasConnected && !self.dockConnected{self.intent.requestStop();self.onDetach?()}
            self.scheduleReconciliation()
        }
        for name in [AVCaptureSession.wasInterruptedNotification,AVCaptureSession.runtimeErrorNotification] {
            NotificationCenter.default.publisher(for:name).receive(on:DispatchQueue.main).sink{[weak self] _ in
                guard let self,self.cameraRunning || self.isTransitioning else{return}
                self.message="The camera was interrupted. Tap Start camera to resume."
                self.intent.requestStop();self.scheduleReconciliation();self.onInterruption?()
            }.store(in:&notifications)
        }
    }
    func setForeground(_ foreground:Bool) {
        if intent.isForeground != foreground{lastTrackingRequest=nil}
        intent.setForeground(foreground);scheduleReconciliation()
    }
    func startCapture() {
        guard !isTransitioning else{return}
        message=nil;intent.requestStart();scheduleReconciliation()
    }
    func stopCapture(){intent.requestStop();scheduleReconciliation()}
    private func scheduleReconciliation() {
        revision &+= 1;captureRequested=intent.shouldCapture
        if !intent.shouldCapture{observation=nil;gaze.reset();horizontalFocus=0;verticalFocus=0;detectedFaces=0;dockTrackingSubjects=0}
        guard reconciliationTask == nil else{return}
        reconciliationTask=Task{[weak self] in
            guard let self else{return}
            await self.reconcile();self.reconciliationTask=nil
        }
    }
    private func reconcile() async {
        var processedRevision:UInt64
        repeat {
            processedRevision=revision
            if intent.shouldCapture && !cameraRunning {
                cameraPhase = .starting
                let allowed=await CameraService.requestPermission()
                guard intent.shouldCapture else{cameraPhase = .off;continue}
                if !allowed {
                    message="Camera access is not allowed. You can change this in iPhone Settings."
                    intent.requestStop();captureRequested=false;cameraPhase = .off
                }else{
                    do {
                        try await camera.start();cameraRunning=true
                        cameraPhase=intent.shouldCapture ? .on:.stopping
                    }catch{
                        await camera.stop();cameraRunning=false;cameraPhase = .off
                        intent.requestStop();captureRequested=false;message=error.localizedDescription
                    }
                }
            }
            if !intent.shouldCapture && cameraRunning {
                cameraPhase = .stopping
                await camera.stop();cameraRunning=false;cameraPhase = .off
                observation=nil;gaze.reset();horizontalFocus=0;verticalFocus=0;detectedFaces=0;dockTrackingSubjects=0
            }
            let wantsTracking=cameraRunning && intent.shouldCapture && dock.isConnected && dock.trackingButtonEnabled
            if lastTrackingRequest != wantsTracking, !wantsTracking || Date()>=trackingRetryAt {
                do{
                    try await dock.setTrackingEnabled(wantsTracking)
                    lastTrackingRequest=wantsTracking;trackingEnabled=wantsTracking;trackingRetryAt = .distantPast
                }catch{
                    lastTrackingRequest=nil;trackingEnabled=nil;trackingRetryAt=Date().addingTimeInterval(2)
                    dockMessage=L10n.format("Could not verify tracking settings: %@",error.localizedDescription)
                }
            }
        }while processedRevision != revision
    }
}
