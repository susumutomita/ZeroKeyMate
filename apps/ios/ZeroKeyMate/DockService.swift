import Foundation
import MateCore

#if canImport(DockKit) && !targetEnvironment(simulator)
import DockKit
import Spatial

/// All DockKit writes are called by MateModel's single reconciliation task.
/// Docking alone does not authorize camera capture.
@MainActor
final class DockService {
    private var observationTask: Task<Void, Never>?
    private var accessory: DockAccessory?
    private var trackingTask:Task<Void,Never>?
    private var motionTask:Task<Void,Never>?
    private var motion:(state:DockAccessory.MotionState,received:TimeInterval)?
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
                            self.motionTask?.cancel();self.motion=nil
                            self.motionTask=Task{[weak self] in
                                do {
                                    for await state in try accessory.motionStates {
                                        guard let self,!Task.isCancelled,self.accessory == accessory else{return}
                                        self.motion=state.error == nil ? (state,ProcessInfo.processInfo.systemUptime):nil
                                    }
                                }catch{if self?.accessory == accessory{self?.motion=nil}}
                            }
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
                        self.motionTask?.cancel();self.motionTask=nil;self.motion=nil
                        self.accessory = nil
                        self.trackingButtonEnabled = false
                    }
                    onChange(nil)
                }
            } catch {
                self?.accessory = nil
                self?.motionTask?.cancel();self?.motion=nil
                self?.trackingButtonEnabled = false
                onChange("DockKit: \(error.localizedDescription)")
            }
            self?.observationTask = nil
        }
    }

    func setTrackingEnabled(_ enabled: Bool) async throws {
        try await DockAccessoryManager.shared.setSystemTrackingEnabled(enabled)
    }

    /// Called only from the same reconciliation task that disables tracking.
    /// False means unsupported/no fresh stationary telemetry, never motor success.
    func performReaction(_ outcome:CompanionOutcome,mayContinue:()->Bool) async throws -> Bool {
        guard let target=accessory,mayContinue() else{return false}
        let original=try target.limits
        let axis=outcome == .confirmed ? original.pitch:original.yaw
        guard let axis else{return false}
        var changedLimits=false
        var progress:Progress?
        func check() throws {
            guard mayContinue(),accessory == target,!Task.isCancelled else{throw CancellationError()}
        }
        func stationary(_ state:DockAccessory.MotionState)->Bool {
            let v=state.angularVelocities
            return abs(v.x)<0.02 && abs(v.y)<0.02 && abs(v.z)<0.02
        }
        do {
            try check()
            try await target.setAngularVelocity(Vector3D(x:0,y:0,z:0))
            let stoppedAt=ProcessInfo.processInfo.systemUptime
            while true {
                try check()
                if let motion,motion.received>=stoppedAt,stationary(motion.state){break}
                if ProcessInfo.processInfo.systemUptime-stoppedAt>0.6{return false}
                try await Task.sleep(for:.milliseconds(40))
            }
            try check()
            guard let center=motion?.state.angularPositions,
                  center.x.isFinite,center.y.isFinite,center.z.isFinite,
                  let plan=DockReactionPlan(center:outcome == .confirmed ? center.x:center.y,
                    range:axis.positionRange,maximumSpeed:axis.maximumSpeed) else{return false}
            let limited=try DockAccessory.Limits.Limit(positionRange:plan.permittedRange,maximumSpeed:plan.maximumSpeed)
            func held(_ value:Double,_ limit:DockAccessory.Limits.Limit?) throws -> DockAccessory.Limits.Limit? {
                guard let limit else{return nil}
                guard limit.positionRange.contains(value) else{throw ProductError.unavailable("The stand position could not be verified.")}
                let lower=max(limit.positionRange.lowerBound,value-0.001)
                let upper=min(limit.positionRange.upperBound,value+0.001)
                return try .init(positionRange:lower..<upper,maximumSpeed:min(limit.maximumSpeed,0.1))
            }
            let limits=try DockAccessory.Limits(yaw:outcome == .rejected ? limited:held(center.y,original.yaw),
                pitch:outcome == .confirmed ? limited:held(center.x,original.pitch),roll:held(center.z,original.roll))
            try check();changedLimits=true;try target.setLimits(limits)
            for value in plan.positions {
                try check()
                let rotation=Vector3D(x:outcome == .confirmed ? value:center.x,
                    y:outcome == .rejected ? value:center.y,z:center.z)
                let began=ProcessInfo.processInfo.systemUptime
                progress=try await target.setOrientation(rotation,duration:.milliseconds(800),relative:false)
                repeat {
                    try check()
                    if progress?.isCancelled == true{throw CancellationError()}
                    if ProcessInfo.processInfo.systemUptime-began>1.2 {
                        throw ProductError.unavailable("The stand reaction did not finish in time.")
                    }
                    try await Task.sleep(for:.milliseconds(40))
                }while progress?.isFinished != true || ProcessInfo.processInfo.systemUptime-began<plan.stepSeconds
            }
            try check()
            try await target.setAngularVelocity(Vector3D(x:0,y:0,z:0))
            try target.setLimits(original);changedLimits=false
            return true
        }catch{
            progress?.cancel()
            // Progress cancellation alone is not proof that physical motion stopped.
            do {
                try await target.setAngularVelocity(Vector3D(x:0,y:0,z:0))
                if changedLimits{try target.setLimits(original)}
            }catch{throw ProductError.unavailable("The stand stop could not be verified. Rest Mate before trying again.")}
            throw error
        }
    }

    deinit {
        observationTask?.cancel();trackingTask?.cancel();motionTask?.cancel()
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
    func performReaction(_ outcome:CompanionOutcome,mayContinue:()->Bool) async throws -> Bool {
        throw DockUnavailable.unsupported
    }
}

private enum DockUnavailable: LocalizedError {
    case unsupported

    var errorDescription: String? {
        "DockKit is unavailable in this environment."
    }
}
#endif
