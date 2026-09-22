import AVFoundation
import Foundation
import Speech
import XCTest
@testable import ZeroKeyMate

@MainActor
private final class ControlledSpeechInput: OnDeviceSpeechRecognizing {
    var partial: (@MainActor @Sendable (String) -> Void)?
    var failure: (@MainActor @Sendable () -> Void)?
    var final: CheckedContinuation<String, Error>?
    var stopped = false
    var startWait: CheckedContinuation<Void, Never>?
    var delayStart = false
    func start(onPartial: @escaping @MainActor @Sendable (String) -> Void,
               onAudioActivity: @escaping @MainActor @Sendable () -> Void,
               onFailure: @escaping @MainActor @Sendable () -> Void) async throws {
        partial = onPartial; failure = onFailure
        if delayStart { await withCheckedContinuation { startWait = $0 } }
    }
    func finish() async throws -> String {
        try await withCheckedThrowingContinuation { final = $0 }
    }
    func stop() { stopped = true }
    func resolve(_ value: String) { final?.resume(returning: value); final = nil }
}

@MainActor
final class LiveSpeechTests: XCTestCase {
    func testFinalizedCorrectionIsSubmittedOnceInsteadOfVolatilePurchaseText() async throws {
        let input = ControlledSpeechInput()
        let voice = VoiceService(authorize: { _ in true }, prepareInput: { _ in input })
        var submitted: [String] = []
        voice.onFinal = { submitted.append($0) }
        await voice.start(locale: "en-US")
        XCTAssertTrue(voice.listening)
        input.partial?("Buy beer")
        voice.finish()
        try await waitUntil { input.final != nil }
        XCTAssertTrue(submitted.isEmpty)
        voice.finish() // An extra tap must not start another finalization.
        input.resolve("Don't buy beer.")
        try await waitUntil { !voice.listening }
        XCTAssertEqual(submitted, ["Don't buy beer."])
        input.partial?("Buy beer")
        XCTAssertEqual(submitted.count, 1)
        XCTAssertTrue(input.stopped)
    }
    func testStopDuringFinalizationIgnoresLateTextAndErrors() async throws {
        let input = ControlledSpeechInput()
        let voice = VoiceService(authorize: { _ in true }, prepareInput: { _ in input })
        var submissions = 0
        voice.onFinal = { _ in submissions += 1 }
        await voice.start(locale: "ja-JP")
        input.partial?("ビールを買って")
        voice.finish()
        try await waitUntil { input.final != nil }
        voice.stop()
        input.resolve("ビールを買って")
        input.failure?()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(submissions, 0)
        XCTAssertFalse(voice.listening)
        XCTAssertFalse(voice.requestingPermission)
        XCTAssertNil(voice.errorMessage)
    }
    func testStopDuringPreparationCannotStartARecorder() async {
        let input = ControlledSpeechInput()
        var preparation: CheckedContinuation<Void, Never>?
        let voice = VoiceService(authorize: { _ in true }, prepareInput: { _ in
            await withCheckedContinuation { preparation = $0 }
            return input
        })
        let start = Task { await voice.start(locale: "en-US") }
        while preparation == nil { await Task.yield() }
        voice.stop()
        preparation?.resume()
        await start.value
        XCTAssertTrue(input.stopped)
        XCTAssertNil(input.partial)
        XCTAssertFalse(voice.listening)
    }
    func testStopDuringStartCannotRestoreListening() async throws {
        let input = ControlledSpeechInput(); input.delayStart = true
        let voice = VoiceService(authorize: { _ in true }, prepareInput: { _ in input })
        let start = Task { await voice.start(locale: "en-US") }
        try await waitUntil { input.startWait != nil }
        voice.stop()
        input.startWait?.resume()
        await start.value
        XCTAssertTrue(input.stopped)
        XCTAssertFalse(voice.listening)
        XCTAssertFalse(voice.requestingPermission)
    }
    func testFinalizationTimeoutDoesNotSubmitAnUnconfirmedOrder() async throws {
        let input = ControlledSpeechInput()
        let voice = VoiceService(authorize: { _ in true }, prepareInput: { _ in input })
        var submissions = 0
        voice.onFinal = { _ in submissions += 1 }
        await voice.start(locale: "en-US")
        input.partial?("Buy beer")
        voice.finish()
        try await waitUntil { input.final != nil }
        try await Task.sleep(for: .milliseconds(3_100))
        XCTAssertFalse(voice.listening)
        XCTAssertNotNil(voice.errorMessage)
        input.resolve("Buy beer")
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(submissions, 0)
    }
    func testAudioConversionHasOwnedBuffersAndBoundedBackpressure() async throws {
        let source = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let target = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: source, frameCapacity: 480))
        buffer.frameLength = 480
        for i in 0..<480 { buffer.floatChannelData![0][i] = 0.02 }
        let bridge = try SpeechAudioBridge(source: source, target: target)
        bridge.append(buffer)
        // A real microphone tap reuses the input storage after returning.
        for i in 0..<480 {buffer.floatChannelData![0][i] = 0}
        bridge.finish()
        var samples = 0
        var audibleSamples = 0
        for try await input in bridge.inputs {
            XCTAssertEqual(input.buffer.format.sampleRate, 16_000)
            XCTAssertFalse(input.buffer === buffer)
            samples += Int(input.buffer.frameLength)
            if let pcm=input.buffer.int16ChannelData {
                audibleSamples += (0..<Int(input.buffer.frameLength)).filter{abs(Int(pcm[0][$0]))>100}.count
            }
        }
        XCTAssertGreaterThan(samples, 0)
        XCTAssertGreaterThan(audibleSamples,0,"The converter must retain owned audio, not a reused microphone buffer")
        XCTAssertLessThanOrEqual(samples, 160)
        let overflow = try SpeechAudioBridge(source: source, target: target)
        for _ in 0..<5_000 { overflow.append(buffer) }
        overflow.finish()
        do {
            for try await _ in overflow.inputs {}
            XCTFail("Missing audio must fail closed")
        } catch { XCTAssertTrue(error is ProductError) }
    }
    func testReportInstalledSpeechLocalesWithoutStartingCapture() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Physical model availability is checked only on the phone")
        #else
        let locales = await SpeechTranscriber.installedLocales.map(\.identifier).sorted()
        let evidence = XCTAttachment(string: "OS: \(ProcessInfo.processInfo.operatingSystemVersionString)\nSpeechTranscriber available: \(SpeechTranscriber.isAvailable)\nInstalled locales: \(locales.joined(separator: ", "))")
        evidence.name = "speech-model-availability"; evidence.lifetime = .keepAlways; add(evidence)
        #endif
    }
    private func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0..<100 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Speech state did not settle")
    }
}
