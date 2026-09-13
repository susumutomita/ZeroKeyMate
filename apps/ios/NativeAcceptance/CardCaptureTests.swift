import XCTest
import MateCore
@testable import ZeroKeyMate

private actor GatedCamera: CameraCapturing {
    var holdStart = false
    var holdStop = false
    private var startGate: CheckedContinuation<Void, Never>?
    private var stopGate: CheckedContinuation<Void, Never>?
    private(set) var starts = 0
    func setObserver(_ observer: @escaping @Sendable (FrameObservation) -> Void) { }
    func gateStart() { holdStart = true }
    func gateStop() { holdStop = true }
    func start() async throws {
        starts += 1
        if holdStart { await withCheckedContinuation { startGate = $0 } }
    }
    func stop() async {
        if holdStop { await withCheckedContinuation { stopGate = $0 } }
    }
    func releaseStart() { holdStart = false; startGate?.resume(); startGate = nil }
    func releaseStop() { holdStop = false; stopGate?.resume(); stopGate = nil }
    var startWaiting: Bool { startGate != nil }
    var stopWaiting: Bool { stopGate != nil }
}

@MainActor private final class UnresponsiveStand: DockControlling {
    var isConnected = true
    var trackingButtonEnabled = true
    var onTrackingSubjects: ((Int) -> Void)?
    private var callback: (@MainActor (String?) -> Void)?
    var blockNext = false
    private var gate: CheckedContinuation<Void, Never>?
    private(set) var trackingCalls: [Bool] = []
    private(set) var stopped = false
    var waiting: Bool { gate != nil }
    func observe(onChange: @escaping @MainActor (String?) -> Void) { callback = onChange; onChange(nil) }
    func setTrackingEnabled(_ enabled: Bool) async throws {
        trackingCalls.append(enabled)
        if blockNext { blockNext = false; await withCheckedContinuation { gate = $0 } }
    }
    func release() { gate?.resume(); gate = nil }
    func detach() { isConnected = false; callback?(nil) }
    func stopMotionForInput() async throws { stopped = true }
    func performReaction(_ outcome: CompanionOutcome, mayContinue: () -> Bool) async throws -> Bool { false }
}

@MainActor final class CardCaptureTests: XCTestCase {
    private func wait(_ condition: @escaping () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !(await condition()) {
            guard ContinuousClock.now < deadline else { XCTFail("State did not settle"); throw CameraError.stopTimedOut }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
    private func model(_ camera: GatedCamera, _ stand: UnresponsiveStand) -> MateModel {
        let mate = MateModel(camera: camera, dock: stand, cameraPermission: { true }, observeSystem: false)
        mate.setForeground(true)
        mate.setStandMovementEnabled(true)
        return mate
    }
    func testCardPreparationStopsCameraWhileStandCommandNeverResponds() async throws {
        let camera = GatedCamera(), stand = UnresponsiveStand()
        let mate = model(camera, stand)
        let started = await mate.startCaptureAndWait(); XCTAssertTrue(started)
        try await wait { mate.trackingEnabled == true }
        stand.blockNext = true
        mate.setApprovalPending(true)
        try await wait { stand.waiting }
        defer { stand.release() }
        try await mate.stopCaptureAndWait(timeout: .seconds(1))
        XCTAssertEqual(mate.cameraPhase, .off)
        XCTAssertFalse(mate.captureRequested)
        XCTAssertTrue(stand.waiting, "The camera must not wait for the blocked motor command")
        stand.release()
        try await wait { stand.stopped }
        XCTAssertEqual(mate.cameraPhase, .off)
        XCTAssertEqual(stand.trackingCalls.last, false)
    }
    func testCameraOffIsNotReportedUntilActualStopAndPreparationHasDeadline() async throws {
        let camera = GatedCamera(), stand = UnresponsiveStand()
        let mate = model(camera, stand)
        let started = await mate.startCaptureAndWait(); XCTAssertTrue(started)
        await camera.gateStop()
        do {
            try await mate.stopCaptureAndWait(timeout: .milliseconds(80))
            XCTFail("Accepted a camera that is still stopping")
        } catch { XCTAssertEqual(error as? CameraError, .stopTimedOut) }
        XCTAssertEqual(mate.cameraPhase, .stopping)
        await camera.releaseStop()
        try await wait { mate.cameraPhase == .off }
        XCTAssertFalse(mate.captureRequested)
    }
    func testStopDuringCameraStartupAndDetachNeverRestartsCapture() async throws {
        let camera = GatedCamera(), stand = UnresponsiveStand()
        await camera.gateStart()
        let mate = model(camera, stand)
        mate.startCapture()
        try await wait { await camera.startWaiting }
        mate.stopCapture()
        stand.detach()
        await camera.releaseStart()
        try await mate.stopCaptureAndWait(timeout: .seconds(1))
        mate.setForeground(false); mate.setForeground(true)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(mate.cameraPhase, .off)
        XCTAssertFalse(mate.captureRequested)
        let starts = await camera.starts; XCTAssertEqual(starts, 1)
    }
    func testCancelledPreparationDoesNotAuthorizeNFC() async throws {
        let camera = GatedCamera(), stand = UnresponsiveStand()
        let mate = model(camera, stand)
        let preparation = Task { @MainActor in try await mate.stopCaptureAndWait() }
        preparation.cancel()
        do { try await preparation.value; XCTFail("Cancelled preparation succeeded") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
    func testPurchaseGuidanceIsTranslatedAndDoesNotAnnounceUnconfirmedPayment() {
        for phase: ShopCheckout.Phase in [.review, .card, .funding, .proving, .verifying, .paymentApproval, .pending, .complete, .expired, .unavailable] {
            guard let text = phase.spokenGuide else { XCTFail("Missing guide"); continue }
            XCTAssertEqual(L10n.text(text, language: .english), text)
            XCTAssertNotEqual(L10n.text(text, language: .japanese), text)
        }
        XCTAssertNil(ShopCheckout.Phase.paying.spokenGuide)
        XCTAssertNil(ShopCheckout.Phase.preparingCard.spokenGuide)
        for error: Error in [CameraError.stopTimedOut, CardScanError.activationTimedOut] {
            let text = ShopCheckout.explanation(error)
            XCTAssertNotEqual(L10n.text(text, language: .japanese), text)
        }
    }
}
