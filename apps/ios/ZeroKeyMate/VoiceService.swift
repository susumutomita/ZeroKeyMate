@preconcurrency import AVFoundation
@preconcurrency import Speech
import Foundation
import MateCore

@MainActor
final class VoiceService:NSObject,ObservableObject,AVSpeechSynthesizerDelegate {
    @Published private(set) var listening=false
    @Published private(set) var speaking=false
    @Published private(set) var requestingPermission=false
    @Published private(set) var transcript=""
    @Published private(set) var errorMessage:String?
    var onFinal:((String)->Void)?
    var onPlaybackFinished:(()->Void)?
    var onInputInterrupted:(()->Void)?
    var onInputIdle:(()->Void)?
    private let engine=AVAudioEngine()
    private let synthesizer=AVSpeechSynthesizer()
    private var recognizer:SFSpeechRecognizer?
    private var request:SFSpeechAudioBufferRecognitionRequest?
    private var recognition:SFSpeechRecognitionTask?
    private var tapInstalled=false
    private var generation:UInt64=0
    private var turn:VoiceTurn?
    private var modernInput:(any OnDeviceSpeechRecognizing)?
    private var finalizationTask:Task<Void,Never>?
    private var finalizationDeadline:Task<Void,Never>?
    private(set) var recognitionBackend = "none"
    private var deadlineTask:Task<Void,Never>?
    private var pendingUtterances=Set<ObjectIdentifier>()
    private var receivingResponse=false
    private var spokenText=SpokenTextBuffer()
    private let authorize: @MainActor (@escaping @MainActor () -> Bool) async -> Bool
    private let prepareInput: @MainActor (Locale) async -> (any OnDeviceSpeechRecognizing)?
    init(authorize: @escaping @MainActor (@escaping @MainActor () -> Bool) async -> Bool = VoiceService.authorizeInput,
         prepareInput: @escaping @MainActor (Locale) async -> (any OnDeviceSpeechRecognizing)? = { await OnDeviceSpeechInput.prepared(locale:$0) }) {
        self.authorize=authorize;self.prepareInput=prepareInput
        super.init();synthesizer.delegate=self
    }
    private static func authorizeInput(isCurrent: @escaping @MainActor () -> Bool) async -> Bool {
        let microphone=await withCheckedContinuation{continuation in
            AVAudioApplication.requestRecordPermission{continuation.resume(returning:$0)}
        }
        guard microphone,isCurrent() else{return false}
        let speech=await withCheckedContinuation{continuation in
            SFSpeechRecognizer.requestAuthorization{continuation.resume(returning:$0)}
        }
        return speech == .authorized
    }

    func start(locale:String? = nil) async {
        guard !listening,!requestingPermission else {return}
        stop();generation &+= 1
        let token=generation
        requestingPermission=true;errorMessage=nil;transcript=""
        defer {if generation==token{requestingPermission=false}}
        let authorized=await authorize { [weak self] in self?.generation==token }
        guard generation==token else{return}
        guard authorized else {errorMessage="Voice input requires microphone and speech recognition permissions. You can still use the keyboard.";return}
        let inputLocale=Locale(identifier:locale ?? L10n.speechLanguage.speechLocale)
        let modern=await prepareInput(inputLocale)
        guard generation==token else{modern?.stop();return}
        if let modern {
            modernInput=modern
            turn=VoiceTurn(now:ProcessInfo.processInfo.systemUptime,usesAudioActivity:true)
            do {
                try await modern.start(onPartial:{[weak self] text in
                    guard let self,self.generation==token,self.finalizationTask==nil else{return}
                    self.transcript=text
                    self.complete(self.turn?.update(text,now:ProcessInfo.processInfo.systemUptime) ?? .waiting)
                },onAudioActivity:{[weak self] in
                    guard let self,self.generation==token else{return}
                    self.turn?.noteAudioActivity(now:ProcessInfo.processInfo.systemUptime)
                },onFailure:{[weak self] in
                    guard let self,self.generation==token else{return}
                    self.inputFailed()
                })
                guard generation==token else{modern.stop();return}
                recognitionBackend="SpeechTranscriber"
                beginTurn(token:token)
                return
            }catch{
                modern.stop();modernInput=nil;turn=nil
                guard generation==token,!Task.isCancelled else{return}
                // Setup may fail before capture is usable. Try only the existing
                // on-device recognizer, never an online transcription request.
            }
        }
        guard let recognizer=SFSpeechRecognizer(locale:inputLocale),recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else {
            errorMessage="On-device speech recognition is unavailable for the selected language. Continue with the keyboard; audio will not be sent to the cloud.";return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord,mode:.measurement,options:[.defaultToSpeaker,.allowBluetoothHFP])
            try AVAudioSession.sharedInstance().setActive(true)
            let request=SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition=true;request.shouldReportPartialResults=true
            self.recognizer=recognizer;self.request=request
            let input=engine.inputNode;let format=input.outputFormat(forBus:0)
            guard format.sampleRate>0,format.channelCount>0 else {throw ProductError.unavailable("Could not read the microphone input format.")}
            input.installTap(onBus:0,bufferSize:1024,format:format){buffer,_ in request.append(buffer)}
            tapInstalled=true
            recognition=recognizer.recognitionTask(with:request){[weak self] result,error in
                let text=result?.bestTranscription.formattedString
                let final=result?.isFinal ?? false
                let failed=error != nil
                Task{@MainActor [weak self] in
                    guard let self,self.generation==token else{return}
                    if let text{self.transcript=text}
                    if final || text != nil {
                        let outcome=self.turn?.update(self.transcript,now:ProcessInfo.processInfo.systemUptime,final:final) ?? .waiting
                        self.complete(outcome)
                    }
                    if failed,self.generation==token {
                        self.inputFailed()
                    }
                }
            }
            engine.prepare();try engine.start()
            recognitionBackend="SFSpeechRecognizer (on device)"
            beginTurn(token:token)
        }catch{stopListening();errorMessage=error.localizedDescription}
    }
    private func beginTurn(token:UInt64) {
        if turn==nil{turn=VoiceTurn(now:ProcessInfo.processInfo.systemUptime)}
        listening=true
        deadlineTask=Task{[weak self] in
            while !Task.isCancelled {
                do{try await Task.sleep(for:.milliseconds(100))}catch{return}
                guard let self,self.generation==token,self.listening else{return}
                self.complete(self.turn?.poll(now:ProcessInfo.processInfo.systemUptime) ?? .waiting)
            }
        }
    }
    private func inputFailed() {
        stopListening();errorMessage="Voice input was interrupted. You can continue with the keyboard."
        onInputInterrupted?()
    }
    private func complete(_ outcome:VoiceTurn.Outcome) {
        switch outcome {
        case .waiting:break
        case .submit(let text):
            guard let modern=modernInput else{stopListening();onFinal?(text);return}
            guard finalizationTask==nil else{return}
            deadlineTask?.cancel();deadlineTask=nil
            let token=generation
            finalizationTask=Task{[weak self] in
                do {
                    let final=try await modern.finish().trimmingCharacters(in:.whitespacesAndNewlines)
                    guard let self,self.generation==token,!Task.isCancelled else{return}
                    self.transcript=final
                    self.stopListening()
                    if final.isEmpty{self.onInputIdle?()}else{self.onFinal?(final)}
                }catch{
                    guard let self,self.generation==token,!Task.isCancelled else{return}
                    self.inputFailed()
                }
            }
            finalizationDeadline=Task{[weak self] in
                do{try await Task.sleep(for:.seconds(3))}catch{return}
                guard let self,self.generation==token else{return}
                self.inputFailed()
            }
        case .silence:
            // Renew only inside the explicitly started session owned by CompanionModel.
            stopListening();onInputIdle?()
        }
    }
    func finish() {
        guard listening else{return}
        complete(.submit(transcript))
    }
    private func stopListening(){
        generation &+= 1;requestingPermission=false
        deadlineTask?.cancel();deadlineTask=nil;turn=nil
        finalizationDeadline?.cancel();finalizationDeadline=nil
        finalizationTask?.cancel();finalizationTask=nil
        modernInput?.stop();modernInput=nil
        if engine.isRunning{engine.stop()}
        if tapInstalled{engine.inputNode.removeTap(onBus:0);tapInstalled=false}
        request?.endAudio();recognition?.cancel();recognition=nil;request=nil;recognizer=nil
        listening=false
        try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)
    }
    func speak(_ text:String,locale:String? = nil){
        stop()
        enqueue(text,locale:locale)
    }
    /// Snapshots are cumulative; only complete sentences enter the speech queue.
    /// The audio session stays active between sentences until generation ends.
    func stream(_ snapshot:String,locale:String? = nil) {
        if !receivingResponse {stop();receivingResponse=true}
        for sentence in spokenText.consume(snapshot) {
            guard receivingResponse else{return}
            enqueue(sentence,locale:locale)
        }
    }
    func finishStream(_ text:String,locale:String? = nil) {
        if !receivingResponse {speak(text,locale:locale);return}
        for sentence in spokenText.consume(text,final:true) {
            guard receivingResponse else{return}
            enqueue(sentence,locale:locale)
        }
        receivingResponse=false
        finishPlaybackIfReady()
    }
    private func enqueue(_ text:String,locale:String?) {
        guard !text.isEmpty else{return}
        do {
            if pendingUtterances.isEmpty {
                try AVAudioSession.sharedInstance().setCategory(.playback,mode:.spokenAudio)
                try AVAudioSession.sharedInstance().setActive(true)
            }
            let utterance=AVSpeechUtterance(string:text)
            utterance.voice=AVSpeechSynthesisVoice(language:locale ?? L10n.speechLanguage.speechLocale);utterance.rate=0.49
            pendingUtterances.insert(ObjectIdentifier(utterance));speaking=true;synthesizer.speak(utterance)
        }catch{stop();errorMessage="Could not start reading aloud.";onInputInterrupted?()}
    }
    private func finishPlaybackIfReady() {
        guard pendingUtterances.isEmpty else{return}
        speaking=false
        guard !receivingResponse else{return}
        try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)
        onPlaybackFinished?()
    }
    func stop(){
        pendingUtterances.removeAll();receivingResponse=false;spokenText=SpokenTextBuffer()
        stopListening();synthesizer.stopSpeaking(at:.immediate);speaking=false
    }
    nonisolated func speechSynthesizer(_ synthesizer:AVSpeechSynthesizer,didFinish utterance:AVSpeechUtterance){
        let identifier = ObjectIdentifier(utterance)
        Task{@MainActor [weak self] in
            guard let self,self.pendingUtterances.remove(identifier) != nil else{return}
            self.finishPlaybackIfReady()
        }
    }
}
