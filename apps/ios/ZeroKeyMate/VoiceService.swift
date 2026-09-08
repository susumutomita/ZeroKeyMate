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
    private var deadlineTask:Task<Void,Never>?
    private var currentUtterance:AVSpeechUtterance?
    override init(){super.init();synthesizer.delegate=self}

    func start(locale:String? = nil) async {
        guard !listening,!requestingPermission else {return}
        stop();generation &+= 1
        let token=generation
        requestingPermission=true;errorMessage=nil;transcript=""
        defer {if generation==token{requestingPermission=false}}
        let microphone=await withCheckedContinuation{continuation in
            AVAudioApplication.requestRecordPermission{continuation.resume(returning:$0)}
        }
        guard generation==token else{return}
        guard microphone else{errorMessage="Microphone access is not allowed. You can still type a message.";return}
        let speech=await withCheckedContinuation{continuation in
            SFSpeechRecognizer.requestAuthorization{continuation.resume(returning:$0)}
        }
        guard generation==token else{return}
        guard microphone,speech == .authorized else {errorMessage="Voice input requires microphone and speech recognition permissions. You can still use the keyboard.";return}
        guard let recognizer=SFSpeechRecognizer(locale:Locale(identifier:locale ?? L10n.speechLanguage.speechLocale)),recognizer.isAvailable,
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
            turn=VoiceTurn(now:ProcessInfo.processInfo.systemUptime)
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
                        self.stopListening();self.errorMessage="Voice input was interrupted. You can continue with the keyboard."
                        self.onInputInterrupted?()
                    }
                }
            }
            engine.prepare();try engine.start();listening=true
            deadlineTask=Task{[weak self] in
                while !Task.isCancelled {
                    do{try await Task.sleep(for:.milliseconds(250))}catch{return}
                    guard let self,self.generation==token,self.listening else{return}
                    self.complete(self.turn?.poll(now:ProcessInfo.processInfo.systemUptime) ?? .waiting)
                }
            }
        }catch{stopListening();errorMessage=error.localizedDescription}
    }
    private func complete(_ outcome:VoiceTurn.Outcome) {
        switch outcome {
        case .waiting:break
        case .submit(let text):stopListening();onFinal?(text)
        case .silence:
            // Renew only inside the explicitly started session owned by CompanionModel.
            stopListening();onInputIdle?()
        }
    }
    @discardableResult func finish() -> String {
        let value=transcript;stopListening();return value
    }
    private func stopListening(){
        generation &+= 1;requestingPermission=false
        deadlineTask?.cancel();deadlineTask=nil;turn=nil
        if engine.isRunning{engine.stop()}
        if tapInstalled{engine.inputNode.removeTap(onBus:0);tapInstalled=false}
        request?.endAudio();recognition?.cancel();recognition=nil;request=nil;recognizer=nil
        listening=false
        try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)
    }
    func speak(_ text:String,locale:String? = nil){
        stopListening();synthesizer.stopSpeaking(at:.immediate)
        guard !text.isEmpty else{return}
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback,mode:.spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            let utterance=AVSpeechUtterance(string:text)
            utterance.voice=AVSpeechSynthesisVoice(language:locale ?? L10n.speechLanguage.speechLocale);utterance.rate=0.49
            currentUtterance=utterance;speaking=true;synthesizer.speak(utterance)
        }catch{currentUtterance=nil;speaking=false;errorMessage="Could not start reading aloud.";onInputInterrupted?()}
    }
    func stop(){stopListening();synthesizer.stopSpeaking(at:.immediate);currentUtterance=nil;speaking=false}
    nonisolated func speechSynthesizer(_ synthesizer:AVSpeechSynthesizer,didFinish utterance:AVSpeechUtterance){
        let identifier = ObjectIdentifier(utterance)
        Task{@MainActor [weak self] in
            guard let self, let current = self.currentUtterance, ObjectIdentifier(current) == identifier else{return}
            self.currentUtterance=nil;self.speaking=false
            try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)
            self.onPlaybackFinished?()
        }
    }
}
