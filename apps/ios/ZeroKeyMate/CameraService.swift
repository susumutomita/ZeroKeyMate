import AVFoundation

/// Owns the entire capture pipeline off the main actor. No file, microphone,
/// network, or sample-buffer consumer is installed in this first slice.
actor CameraService {
    private let session = AVCaptureSession()
    private var configured = false

    static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    func start() throws {
        if !configured {
            try configure()
        }
        guard !session.isRunning else { return }
        session.startRunning()
        guard session.isRunning && !session.isInterrupted else {
            session.stopRunning()
            throw CameraError.unavailable
        }
    }

    func stop() {
        if session.isRunning {
            session.stopRunning()
        }
    }

    private func configure() throws {
        guard let camera = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: .front
        ) else {
            throw CameraError.noFrontCamera
        }
        let input = try AVCaptureDeviceInput(device: camera)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.vga640x480) {
            session.sessionPreset = .vga640x480
        }
        guard session.canAddInput(input) else { throw CameraError.unavailable }
        session.addInput(input)
        guard session.canAddOutput(output) else {
            session.removeInput(input)
            throw CameraError.unavailable
        }
        session.addOutput(output)
        configured = true
    }
}

private enum CameraError: LocalizedError {
    case noFrontCamera
    case unavailable

    var errorDescription: String? {
        switch self {
        case .noFrontCamera:
            return "フロントカメラを利用できません。カメラ操作は実機で確認してください。"
        case .unavailable:
            return "カメラを開始できませんでした。他のカメラアプリを閉じて再試行してください。"
        }
    }
}
