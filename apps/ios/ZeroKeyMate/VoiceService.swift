@preconcurrency import AVFoundation
@preconcurrency import Speech
import Foundation

@MainActor
final class VoiceService:NSObject,ObservableObject,AVSpeechSynthesizerDelegate {
    @Published private(set) var listening=false
    @Published private(set) var speaking=false
    @Published private(set) var requestingPermission=false
    @Published private(set) var transcript=""
    @Published private(set) var errorMessage:String?
    var onFinal:((String)->Void)?
    private let engine=AVAudioEngine()
    private let synthesizer=AVSpeechSynthesizer()
    private var recognizer:SFSpeechRecognizer?
    private var request:SFSpeechAudioBufferRecognitionRequest?
    private var recognition:SFSpeechRecognitionTask?
    private var tapInstalled=false
    private var generation:UInt64=0
    private var currentUtterance:AVSpeechUtterance?
    override init(){super.init();synthesizer.delegate=self}

    func start() async {
        guard !listening,!requestingPermission else {return}
        stop();generation &+= 1
        let token=generation
        requestingPermission=true;errorMessage=nil;transcript=""
        defer {if generation==token{requestingPermission=false}}
        let microphone=await withCheckedContinuation{continuation in
            AVAudioApplication.requestRecordPermission{continuation.resume(returning:$0)}
        }
        guard generation==token else{return}
        let speech=await withCheckedContinuation{continuation in
            SFSpeechRecognizer.requestAuthorization{continuation.resume(returning:$0)}
        }
        guard generation==token else{return}
        guard microphone,speech == .authorized else {errorMessage="音声入力にはマイクと音声認識の許可が必要です。入力ボタンから文字でも会話できます。";return}
        guard let recognizer=SFSpeechRecognizer(locale:Locale(identifier:"ja-JP")),recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else {
            errorMessage="日本語の端末内音声認識を利用できません。音声をクラウドへ送らず、文字入力で続けてください。";return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord,mode:.measurement,options:[.defaultToSpeaker,.allowBluetoothHFP])
            try AVAudioSession.sharedInstance().setActive(true)
            let request=SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition=true;request.shouldReportPartialResults=true
            self.recognizer=recognizer;self.request=request
            let input=engine.inputNode;let format=input.outputFormat(forBus:0)
            guard format.sampleRate>0,format.channelCount>0 else {throw ProductError.unavailable("マイクの入力形式を取得できません。")}
            input.installTap(onBus:0,bufferSize:1024,format:format){buffer,_ in request.append(buffer)}
            tapInstalled=true
            recognition=recognizer.recognitionTask(with:request){[weak self] result,error in
                let text=result?.bestTranscription.formattedString
                let final=result?.isFinal ?? false
                let failed=error != nil
                Task{@MainActor [weak self] in
                    guard let self,self.generation==token else{return}
                    if let text{self.transcript=text}
                    if final {
                        let completed=self.transcript;self.stopListening()
                        if !completed.isEmpty{self.onFinal?(completed)}
                    }else if failed {
                        self.stopListening();self.errorMessage="音声入力が中断されました。文字入力でも続けられます。"
                    }
                }
            }
            engine.prepare();try engine.start();listening=true
        }catch{stopListening();errorMessage=error.localizedDescription}
    }
    @discardableResult func finish() -> String {
        let value=transcript;stopListening();return value
    }
    private func stopListening(){
        generation &+= 1;requestingPermission=false
        if engine.isRunning{engine.stop()}
        if tapInstalled{engine.inputNode.removeTap(onBus:0);tapInstalled=false}
        request?.endAudio();recognition?.cancel();recognition=nil;request=nil;recognizer=nil
        listening=false
        try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)
    }
    func speak(_ text:String){
        stopListening();synthesizer.stopSpeaking(at:.immediate)
        guard !text.isEmpty else{return}
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback,mode:.spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            let utterance=AVSpeechUtterance(string:text)
            utterance.voice=AVSpeechSynthesisVoice(language:"ja-JP");utterance.rate=0.49
            currentUtterance=utterance;speaking=true;synthesizer.speak(utterance)
        }catch{errorMessage="読み上げを開始できませんでした。"}
    }
    func stop(){stopListening();synthesizer.stopSpeaking(at:.immediate);currentUtterance=nil;speaking=false}
    nonisolated func speechSynthesizer(_ synthesizer:AVSpeechSynthesizer,didFinish utterance:AVSpeechUtterance){
        let identifier = ObjectIdentifier(utterance)
        Task{@MainActor [weak self] in
            guard let self, let current = self.currentUtterance, ObjectIdentifier(current) == identifier else{return}
            self.currentUtterance=nil;self.speaking=false
            try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)
        }
    }
}
