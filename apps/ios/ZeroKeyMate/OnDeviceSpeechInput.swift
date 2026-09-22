@preconcurrency import AVFoundation
@preconcurrency import Speech
import Foundation
import MateCore

/// The new Apple speech model is used when its locale assets are installed.
/// Download preparation never receives audio; an unavailable model uses the
/// existing on-device recognizer for that turn, rather than a cloud service.
@MainActor
protocol OnDeviceSpeechRecognizing: AnyObject {
    func start(onPartial: @escaping @MainActor @Sendable (String) -> Void,
               onAudioActivity: @escaping @MainActor @Sendable () -> Void,
               onFailure: @escaping @MainActor @Sendable () -> Void) async throws
    func finish() async throws -> String
    func stop()
}

@MainActor
final class OnDeviceSpeechInput: OnDeviceSpeechRecognizing {
    private static var assetTasks: [String: Task<Void, Never>] = [:]
    private let transcriber: SpeechTranscriber
    private let analyzer: SpeechAnalyzer
    private let engine = AVAudioEngine()
    private var bridge: SpeechAudioBridge?
    private var resultTask: Task<Void, Error>?
    private var analysisTask: Task<Void, Never>?
    private var transcript = SpeechTranscript()
    private var stopped = false
    private var tapInstalled = false

    static func prepared(locale: Locale) async -> OnDeviceSpeechInput? {
        guard SpeechTranscriber.isAvailable,
              let locale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else { return nil }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults], attributeOptions: [])
        let status = await AssetInventory.status(forModules: [transcriber])
        if status == .installed { return OnDeviceSpeechInput(transcriber: transcriber) }
        guard status != .unsupported, assetTasks[locale.identifier] == nil else { return nil }
        assetTasks[locale.identifier] = Task {
            defer { assetTasks[locale.identifier] = nil }
            do {
                if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                    try await request.downloadAndInstall()
                }
            } catch { /* Keep the on-device fallback; retry preparation on a later explicit turn. */ }
        }
        return nil
    }

    private init(transcriber: SpeechTranscriber) {
        self.transcriber = transcriber
        analyzer = SpeechAnalyzer(modules: [transcriber],
            options: .init(priority: .userInitiated, modelRetention: .whileInUse))
    }

    func start(onPartial: @escaping @MainActor @Sendable (String) -> Void,
               onAudioActivity: @escaping @MainActor @Sendable () -> Void,
               onFailure: @escaping @MainActor @Sendable () -> Void) async throws {
        try Task.checkCancellation()
        try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .measurement,
            options: [.defaultToSpeaker, .allowBluetoothHFP])
        try AVAudioSession.sharedInstance().setActive(true)
        let input = engine.inputNode
        let sourceFormat = input.outputFormat(forBus: 0)
        guard sourceFormat.sampleRate > 0, sourceFormat.channelCount > 0,
              let targetFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
                compatibleWith: [transcriber], considering: sourceFormat) else {
            throw ProductError.unavailable("Could not read the microphone input format.")
        }
        try Task.checkCancellation()
        guard !stopped else { throw CancellationError() }
        try await analyzer.prepareToAnalyze(in: targetFormat)
        try Task.checkCancellation()
        guard !stopped else { throw CancellationError() }
        let bridge = try SpeechAudioBridge(source: sourceFormat, target: targetFormat) { [weak self] in
            Task { @MainActor [weak self] in
                guard self?.stopped == false else { return }
                onAudioActivity()
            }
        }
        self.bridge = bridge
        resultTask = Task { [weak self, transcriber] in
            do {
                for try await result in transcriber.results {
                    try Task.checkCancellation()
                    guard let self, !self.stopped else { return }
                    self.transcript.update(String(result.text.characters), start: result.range.start.seconds,
                        end: CMTimeRangeGetEnd(result.range).seconds, isFinal: result.isFinal)
                    // A final range is not an utterance boundary. The owner
                    // decides when to stop input and explicitly finalize it.
                    onPartial(self.transcript.text)
                }
            } catch {
                if !Task.isCancelled, self?.stopped == false { onFailure() }
                throw error
            }
        }
        analysisTask = Task { [weak self, analyzer] in
            do { try await analyzer.start(inputSequence: bridge.inputs) }
            catch { if !Task.isCancelled, self?.stopped == false { onFailure() } }
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: sourceFormat) { buffer, _ in
            bridge.append(buffer)
        }
        tapInstalled = true
        engine.prepare()
        try engine.start()
    }

    /// Stop capturing first, then wait for the model's corrected final text.
    /// Cancellation never submits a volatile purchase phrase.
    func finish() async throws -> String {
        stopCapture()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        try await resultTask?.value
        try Task.checkCancellation()
        guard !stopped else { throw CancellationError() }
        return transcript.text
    }

    private func stopCapture() {
        if engine.isRunning { engine.stop() }
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        bridge?.finish()
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        stopCapture()
        resultTask?.cancel(); resultTask = nil
        analysisTask?.cancel(); analysisTask = nil
        Task { [analyzer] in await analyzer.cancelAndFinishNow() }
    }
}

/// The audio tap is its sole producer; AVAudioConverter never crosses onto the
/// main actor. Only converted, owned PCM buffers enter a bounded in-memory queue.
final class SpeechAudioBridge: @unchecked Sendable {
    let inputs: AsyncThrowingStream<AnalyzerInput, Error>
    private let continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation
    private let converter: AVAudioConverter
    private let target: AVAudioFormat
    private let modernConvert: ((AVAudioPCMBuffer) throws -> [AnalyzerInput])?
    private let modernFlush: (() throws -> [AnalyzerInput])?
    private let onAudioActivity: @Sendable () -> Void
    private var framesSinceActivity: Double = 0
    private let lock=NSLock()
    private var finished=false
    init(source: AVAudioFormat, target: AVAudioFormat, onAudioActivity: @escaping @Sendable () -> Void = {}) throws {
        guard let converter = AVAudioConverter(from: source, to: target) else { throw ProductError.invalidResponse }
        self.converter = converter; self.target = target; self.onAudioActivity = onAudioActivity
        converter.primeMethod = .none
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            let native=AnalyzerInputConverter(analyzerFormat:target)
            modernConvert={try native.convert($0,at:nil)}
            modernFlush={try native.flush()}
        } else {modernConvert=nil;modernFlush=nil}
        #else
        modernConvert=nil;modernFlush=nil
        #endif
        let pair = AsyncThrowingStream<AnalyzerInput, Error>.makeStream(bufferingPolicy: .bufferingOldest(64))
        inputs = pair.stream; continuation = pair.continuation
    }
    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock();defer{lock.unlock()}
        guard !finished else{return}
        framesSinceActivity += Double(buffer.frameLength)
        if framesSinceActivity >= buffer.format.sampleRate * 0.1,
           let channels = buffer.floatChannelData, buffer.frameLength > 0 {
            var sum: Float = 0
            for index in 0..<Int(buffer.frameLength) { sum += channels[0][index] * channels[0][index] }
            if sqrt(sum / Float(buffer.frameLength)) >= 0.008 {
                framesSinceActivity = 0; onAudioActivity()
            }
        }
        if let modernConvert {
            do {for input in try modernConvert(buffer) {yield(input)}}
            catch {continuation.finish(throwing:ProductError.invalidResponse)}
            return
        }
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * target.sampleRate / buffer.format.sampleRate)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
            continuation.finish(throwing: ProductError.invalidResponse); return
        }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            guard !supplied else { inputStatus.pointee = .noDataNow; return nil }
            supplied = true; inputStatus.pointee = .haveData; return buffer
        }
        guard error == nil, status != .error else {
            continuation.finish(throwing: ProductError.invalidResponse); return
        }
        if output.frameLength > 0 {yield(AnalyzerInput(buffer: output))}
    }
    private func yield(_ input: AnalyzerInput) {
        if case .dropped = continuation.yield(input) {
            // Never silently lose words and submit a different order.
            continuation.finish(throwing: ProductError.invalidResponse)
        }
    }
    // Called only after the tap has been removed, so conversion is no longer
    // running. Flush iOS 27's native converter before closing the sequence.
    func finish() {
        lock.lock();defer{lock.unlock()}
        guard !finished else{return};finished=true
        if let modernFlush {
            do {for input in try modernFlush() {yield(input)}}
            catch {continuation.finish(throwing:ProductError.invalidResponse);return}
        } else {
            for _ in 0..<8 {
                guard let output=AVAudioPCMBuffer(pcmFormat:target,frameCapacity:1024) else{break}
                var error:NSError?
                let status=converter.convert(to:output,error:&error){_,state in state.pointee = .endOfStream;return nil}
                guard error==nil,status != .error else{continuation.finish(throwing:ProductError.invalidResponse);return}
                if output.frameLength>0{yield(AnalyzerInput(buffer:output))}
                if status == .endOfStream || output.frameLength==0{break}
            }
        }
        continuation.finish()
    }
}
