import AVFoundation
import Combine
import Foundation
import MateCore
import UIKit

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
    @Published private(set) var faceDetectionStatus="Waiting for face detection"
    @Published private(set) var dockTrackingSubjects=0
    @Published private(set) var dockTrackingButtonEnabled=false
    @Published private(set) var standMovementEnabled=UserDefaults.standard.object(forKey:"mate-stand-movement") as? Bool ?? true
    @Published private(set) var reactionRunning=false
    private var reactionGate=DockReactionGate()
    private var approvalPending=false
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
    private var trackingOwnership=DockTrackingOwnership()
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
                    self.faceDetectionStatus=value.faceDetectionAvailable ? (value.faceCount>0 ? "I can see a face.":"Looking for a face. Face the front camera.") : "Face detection failed. Rest Mate and try again."
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
        NotificationCenter.default.publisher(for:UIAccessibility.reduceMotionStatusDidChangeNotification)
            .receive(on:DispatchQueue.main).sink{[weak self] _ in self?.scheduleReconciliation()}.store(in:&notifications)
    }
    var standMotionAllowed:Bool {standMovementEnabled && !UIAccessibility.isReduceMotionEnabled}
    private var reactionAllowed:Bool {
        cameraRunning && intent.shouldCapture && dock.isConnected && !approvalPending && standMotionAllowed
    }
    func setApprovalPending(_ pending:Bool) {
        guard approvalPending != pending else{return}
        approvalPending=pending;scheduleReconciliation()
    }
    func setStandMovementEnabled(_ enabled:Bool) {
        standMovementEnabled=enabled;UserDefaults.standard.set(enabled,forKey:"mate-stand-movement")
        scheduleReconciliation()
    }
    func requestReaction(_ outcome:CompanionOutcome) {
        let now=ProcessInfo.processInfo.systemUptime
        guard reactionGate.request(outcome,allowed:reactionAllowed,now:now) else{return}
        scheduleReconciliation()
    }
    func setForeground(_ foreground:Bool) {
        if intent.isForeground != foreground{lastTrackingRequest=nil}
        intent.setForeground(foreground);scheduleReconciliation()
    }
    func startCapture() {
        guard !isTransitioning else{return}
        faceDetectionStatus="Waiting for face detection"
        message=nil;intent.requestStart();scheduleReconciliation()
    }
    func startCaptureAndWait() async -> Bool {
        startCapture()
        // Serialize camera consent before asking for microphone consent. Stop,
        // backgrounding and permission denial all clear captureRequested.
        while captureRequested && cameraPhase != .on {
            do{try await Task.sleep(for:.milliseconds(40))}catch{return false}
        }
        return cameraPhase == .on && captureRequested
    }
    func stopCapture(){intent.requestStop();scheduleReconciliation()}
    private func scheduleReconciliation() {
        revision &+= 1;captureRequested=intent.shouldCapture
        reactionGate.update(allowed:reactionAllowed)
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
                    onInterruption?()
                }else{
                    do {
                        try await camera.start();cameraRunning=true
                        cameraPhase=intent.shouldCapture ? .on:.stopping
                    }catch{
                        await camera.stop();cameraRunning=false;cameraPhase = .off
                        intent.requestStop();captureRequested=false;message=error.localizedDescription
                        onInterruption?()
                    }
                }
            }
            if !intent.shouldCapture && cameraRunning {
                cameraPhase = .stopping
                await camera.stop();cameraRunning=false;cameraPhase = .off
                observation=nil;gaze.reset();horizontalFocus=0;verticalFocus=0;detectedFaces=0;dockTrackingSubjects=0
            }
            // Configure system tracking after an explicit camera start. The physical
            // tracking button is telemetry, not a prerequisite for enabling the API:
            // gating on it can prevent recovery from our earlier disabled state.
            if let request=reactionGate.begin(allowed:reactionAllowed) {
                reactionRunning=true
                let ticket=request.ticket
                do {
                    try await dock.setTrackingEnabled(false)
                    lastTrackingRequest=false;trackingEnabled=false
                    _=trackingOwnership.shouldApply(enabled:true)
                    if reactionGate.permits(ticket,allowed:reactionAllowed) {
                        let performed=try await dock.performReaction(request.outcome){[weak self] in
                            guard let self else{return false}
                            return self.reactionGate.permits(ticket,allowed:self.reactionAllowed)
                        }
                        if !performed{dockMessage="Stand reactions need a supported axis and a fresh stationary position."}
                    }
                }catch is CancellationError {
                    // Rest/detach/settings invalidated this interaction. The adapter
                    // stops its motion before returning; never enqueue it again.
                }catch{
                    dockMessage="The stand reaction stopped. Rest Mate and start again."
                    intent.requestStop();captureRequested=false;revision &+= 1;onInterruption?()
                }
                reactionGate.finish(ticket);reactionRunning=false;lastTrackingRequest=nil
            }
            let ownsCamera=cameraRunning && intent.shouldCapture && dock.isConnected
            // A camera session can start system tracking automatically. Explicitly
            // apply OFF for our active session when movement is disabled.
            if ownsCamera{_=trackingOwnership.shouldApply(enabled:true)}
            let wantsTracking=ownsCamera && !approvalPending && standMotionAllowed
            if trackingOwnership.shouldApply(enabled:wantsTracking),lastTrackingRequest != wantsTracking, !wantsTracking || Date()>=trackingRetryAt {
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
