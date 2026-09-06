@preconcurrency import AVFoundation
import Foundation

/// All capture-session mutation is serialized away from the main actor.
actor CameraService {
    private let session=AVCaptureSession()
    private let analyzer=FrameAnalyzer()
    private var configured=false
    private var observer:(@Sendable (FrameObservation)->Void)?

    static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for:.video) {
        case .authorized:return true
        case .notDetermined:return await AVCaptureDevice.requestAccess(for:.video)
        default:return false
        }
    }
    func setObserver(_ observer:@escaping @Sendable (FrameObservation)->Void) {
        self.observer=observer
    }
    func start() throws {
        if !configured{try configure()}
        analyzer.configure(enabled:true,callback:observer)
        if !session.isRunning{session.startRunning()}
        guard session.isRunning,!session.isInterrupted else {
            analyzer.configure(enabled:false)
            if session.isRunning{session.stopRunning()}
            throw CameraError.unavailable
        }
    }
    func stop() {
        analyzer.configure(enabled:false)
        if session.isRunning{session.stopRunning()}
    }
    private func configure() throws {
        guard let device=AVCaptureDevice.default(.builtInWideAngleCamera,for:.video,position:.front) else {throw CameraError.noFrontCamera}
        let input=try AVCaptureDeviceInput(device:device)
        let output=AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames=true
        output.setSampleBufferDelegate(analyzer,queue:analyzer.queue)
        session.beginConfiguration()
        defer{session.commitConfiguration()}
        guard session.canAddInput(input),session.canAddOutput(output) else {throw CameraError.unavailable}
        session.sessionPreset = .vga640x480
        session.addInput(input);session.addOutput(output)
        configured=true
    }
}

enum CameraError:Error,LocalizedError {
    case noFrontCamera,unavailable
    var errorDescription:String? {
        switch self {
        case .noFrontCamera:return "フロントカメラを利用できません。SimulatorではなくiPhoneで確認してください。"
        case .unavailable:return "カメラを起動できませんでした。ほかのアプリの利用や端末の状態を確認してください。"
        }
    }
}
