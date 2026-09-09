import SwiftUI
import MateCore

private enum Finish {
    static let paper=Color(red:0.958,green:0.954,blue:0.937)
    static let ink=Color(red:0.105,green:0.112,blue:0.112)
    static let secondary=Color(red:0.36,green:0.37,blue:0.36)
    static let rule=Color.black.opacity(0.10)
}

struct MateView:View {
    @StateObject private var model=CompanionModel()
    @AppStorage("mate-companion-introduced") private var introduced=false
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(L10n.preferenceKey) private var language = AppLanguage.english.rawValue
    @AppStorage(L10n.speechPreferenceKey) private var spokenLanguage = AppLanguage.japanese.rawValue
    @Environment(\.locale) private var locale
    var body:some View {
        let _ = locale.identifier
        CompanionHome(model:model,sensors:model.sensors,voice:model.voice)
            .task{if !introduced{model.sheet = .welcome};model.setForeground(scenePhase == .active);await model.start()}
            .onChange(of:language){_,_ in model.rest();model.errorMessage=nil}
            .onChange(of:spokenLanguage){_,_ in model.rest();model.errorMessage=nil}
            .onChange(of:scenePhase){_,value in
                if value == .background{model.setForeground(false)}
                else if value == .active{model.setForeground(true)}
            }
            .sheet(item:$model.sheet){sheet in
                NavigationStack{
                    Group {
                        switch sheet {
                        case .welcome:CompanionWelcomeSheet(model:model)
                        case .controls:ControlsSheet(model:model,sensors:model.sensors,voice:model.voice)
                        case .conversation:ConversationSheet(model:model)
                        case .settings:SettingsSheet(model:model,sensors:model.sensors)
                        case .setup:SetupSheet(model:model,wallet:model.wallet)
                        case .rules:RulesSheet(model:model)
                        case .wallet:WalletSheet(model:model,wallet:model.wallet)
                        case .identity:IdentitySheet(model:model)
                        case .activity:ActivitySheet(model:model)
                        case .disclosure:DisclosureSheet(model:model)
                        case .localProof:LocalProofSheet(proofs:model.proofs) { model.makeDraft(service:.translation) }
                        case .connection:ConnectionSheet(model:model)
                        }
                    }
                    .toolbar{
                        if sheet == .welcome || sheet == .conversation {
                            ToolbarItem(placement:.topBarLeading){Button("Settings"){model.sheet = .settings}.accessibilityIdentifier("open-settings")}
                        }
                        ToolbarItem(placement:.topBarTrailing){Button("Close",systemImage:"xmark"){model.sheet=nil}.labelStyle(.iconOnly).accessibilityIdentifier("close-sheet")}
                    }
                    .toolbarBackground(Finish.paper,for:.navigationBar)
                }
                .tint(Finish.ink).presentationBackground(Finish.paper)
            }
            .alert("Please check",isPresented:Binding(get:{model.errorMessage != nil},set:{if !$0{model.errorMessage=nil}})){
                Button("Close",role:.cancel){model.errorMessage=nil}
            }message:{Text(L10n.text(model.errorMessage ?? ""))}
    }
}

private struct CompanionHome:View {
    @ObservedObject var model:CompanionModel
    @ObservedObject var sensors:MateModel
    @ObservedObject var voice:VoiceService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("mate-companion-introduced") private var introduced=false
    @State private var outcomeOffset:CGSize = .zero
    private var status:String {
        if model.awaitingGreeting{return "Waiting for hello. Microphone on; camera off."}
        if model.preparingCompanion{return "Preparing voice input."}
        if voice.requestingPermission{return "Preparing voice input."}
        return model.activity.label
    }
    var body:some View {
        GeometryReader{geometry in
            MateEyes(resting:model.activity == .resting,listening:model.activity == .listening,
                     thinking:model.activity.processing,
                     focus:sensors.horizontalFocus,verticalFocus:sensors.verticalFocus,reduceMotion:reduceMotion,
                     speaking:model.activity == .speaking,hearingSpeech:model.activity == .listening && !voice.transcript.isEmpty)
                .frame(width:min(geometry.size.width*0.78,620),height:min(geometry.size.height*0.38,300))
                .offset(outcomeOffset)
                .task(id:model.lastOutcome){
                    outcomeOffset = .zero
                    guard !reduceMotion,let outcome=model.lastOutcome else{return}
                    await playOutcomeMotion(outcome)
                }
                .frame(maxWidth:.infinity,maxHeight:.infinity)
                .contentShape(Rectangle())
                .onTapGesture{
                    if !introduced {model.sheet = .welcome}
                    else if model.isResting {Task{await model.startCompanion()}}
                    // An awake companion should not open settings or stop on a tap.
                }
                .simultaneousGesture(DragGesture(minimumDistance:60).onEnded { value in
                    if value.translation.height < -60 {model.sheet = .controls}
                })
                .onLongPressGesture{model.sheet = .controls}
                .accessibilityElement(children:.ignore)
                .accessibilityLabel("Mate")
                .accessibilityValue(L10n.text(status))
                .accessibilityHint("Tap to wake. Say おやすみ to rest. Touch and hold for controls and settings.")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction{
                    if !introduced{model.sheet = .welcome}
                    else if model.isResting{Task{await model.startCompanion()}}
                }
                .accessibilityAction(named:Text("Controls")){model.sheet = .controls}
                .accessibilityAction(named:Text("Rest and stop camera and microphone")){model.rest()}
                .accessibilityIdentifier("companion-face")
        }.background(Finish.paper.ignoresSafeArea()).preferredColorScheme(.light).statusBarHidden()
    }
    /// A short, finite nod or shake on the face only, triggered by a verified
    /// outcome. This never drives the physical stand; it is display-only.
    private func playOutcomeMotion(_ outcome:ExecutionOutcome) async {
        if outcome == .confirmed {
            withAnimation(.easeOut(duration:0.16)){outcomeOffset=CGSize(width:0,height:9)}
            do{try await Task.sleep(for:.milliseconds(160))}catch{outcomeOffset = .zero;return}
            withAnimation(.spring(response:0.22,dampingFraction:0.55)){outcomeOffset = .zero}
        } else {
            for step:CGFloat in [-12,10,-7,5,0] {
                withAnimation(.easeInOut(duration:0.07)){outcomeOffset=CGSize(width:step,height:0)}
                do{try await Task.sleep(for:.milliseconds(70))}catch{outcomeOffset = .zero;return}
            }
        }
    }
}

private struct CompanionWelcomeSheet:View {
    @ObservedObject var model:CompanionModel
    @AppStorage("mate-companion-introduced") private var introduced=false
    var body:some View {
        Form {
            Section {
                Text("Your iPhone. Your companion.").font(.title2)
                Text("While we spend time together, Mate uses the camera to follow your face and the microphone to listen. Everyday conversation is processed on this iPhone.")
                Text("Quiet moments do not end our time together. Say おやすみ to rest and stop the camera and microphone. Removing the stand or leaving the app also stops the session.")
                Text("Tap once to wake Mate. Say おやすみ to rest, then tap to wake again. Touch and hold the face for controls and settings. You can also swipe up for controls.")
            }
            Section {
                Button("Spend time together") {
                    introduced=true;model.sheet=nil
                    Task{await model.startCompanion()}
                }.accessibilityIdentifier("start-companion")
                Button("Type a message"){model.sheet = .conversation}.accessibilityIdentifier("open-conversation")
                Button("Controls"){model.sheet = .controls}.accessibilityIdentifier("open-controls")
            }
            voiceWakeSection
        }.scrollContentBackground(.hidden).background(Finish.paper)
            .navigationTitle("Welcome to Mate").navigationBarTitleDisplayMode(.inline)
    }
    private var voiceWakeSection:some View {
        Section {
            Text("Voice wake keeps the microphone on while this app is open. Say こんにちは to open the eyes and start camera tracking. Other speech is discarded. Choose Stop voice wake, leave the app, or remove the stand to stop listening.")
            Button("Enable voice wake") {
                introduced=true;model.sheet=nil
                Task{await model.armVoiceWake()}
            }.accessibilityIdentifier("enable-voice-wake")
        }
    }
}

private struct ControlsSheet:View {
    @AppStorage("mate-companion-introduced") private var introduced=false
    @ObservedObject var model:CompanionModel
    @ObservedObject var sensors:MateModel
    @ObservedObject var voice:VoiceService
    var body:some View {
        Form {
            Section {
                Button("Spend time together"){
                    introduced=true;model.sheet=nil
                    Task{await model.startCompanion()}
                }.disabled(model.financialBusy || model.preparingCompanion || model.voiceSessionActive)
                    .accessibilityIdentifier("start-companion")
                Button(L10n.text(voice.speaking || model.thinking ? "Interrupt and speak":"Speak now")) {
                    Task{await model.speakNow()}
                }.disabled(model.financialBusy || voice.requestingPermission || model.preparingCompanion)
                    .accessibilityIdentifier("speak-now")
                Button("Read or type a message"){model.sheet = .conversation}.accessibilityIdentifier("open-conversation")
                Button("Rest and stop camera and microphone"){model.rest();model.sheet=nil}
                    .accessibilityIdentifier("rest-button")
            }
            Section {
                Text(L10n.text(model.activity.label)).accessibilityIdentifier("companion-activity")
                if let detail=model.executionStatus,detail != model.activity.label {SectionNote(text:detail)}
                if model.awaitingGreeting{Text("Waiting for hello. Microphone on; camera off.")}
                Text(L10n.text(sensors.cameraPhase == .on ? "Camera on · On-device processing":sensors.cameraPhase == .starting ? "Camera starting":sensors.cameraPhase == .stopping ? "Camera stopping":"Camera off"))
                    .accessibilityIdentifier("camera-status")
                if sensors.cameraPhase == .on {
                    Text(L10n.text(sensors.faceDetectionStatus)).accessibilityIdentifier("face-detection-status")
                    Text(L10n.text(!sensors.dockConnected ? "Stand not connected":!sensors.dockTrackingButtonEnabled ? "Enable tracking with the stand button":sensors.trackingEnabled != true ? "Preparing stand tracking":sensors.dockTrackingSubjects>0 ? "Stand tracking a subject":"Stand looking for a subject"))
                }
                if let error=voice.errorMessage{SectionNote(text:error)}
                if let message=sensors.message{SectionNote(text:message)}
                if let reason=model.modelUnavailable{SectionNote(text:reason)}
            }
            if let consent=model.agentDelegation {
                Section("Agent permission") {
                    Text("One approved shop · up to \(TokenAmount(units:consent.maximumAmount).display) test USDC per request")
                    Text("Expires: \(Date(timeIntervalSince1970:Double(consent.validUntil)).formatted())").font(.footnote)
                    Button("Stop automatic orders",role:.destructive){model.stopAgentDelegation()}
                }
            }
            Section {
                Button(L10n.text(UserDefaults.standard.string(forKey:model.setupCheckpointKey) == nil ? "Set up external requests":"Resume external request setup")){model.sheet = .setup}.accessibilityIdentifier("open-setup")
                Button("Settings"){model.sheet = .settings}.accessibilityIdentifier("open-settings")
                Button("How Mate works"){model.sheet = .welcome}.accessibilityIdentifier("open-welcome")
                if let draft=model.draft {
                    Button(L10n.format("Review %@ request",L10n.text(draft.service.title))){model.sheet = .disclosure}
                }
            }
            Section {
                Text("Voice wake keeps the microphone on while this app is open. Say こんにちは to open the eyes and start camera tracking. Other speech is discarded. Choose Stop voice wake, leave the app, or remove the stand to stop listening.")
                Button("Enable voice wake") {
                    introduced=true;model.sheet=nil
                    Task{await model.armVoiceWake()}
                }.disabled(model.voiceSessionActive || model.financialBusy || model.thinking)
                    .accessibilityIdentifier("enable-voice-wake")
                if model.awaitingGreeting {
                    Button("Stop voice wake"){model.rest()}.accessibilityIdentifier("stop-voice-wake")
                }
            }
            Section {
                Text("Speak now stops the current reply and listens on this iPhone. Listening continues after replies until you choose Rest. Speaking over a reply does not interrupt it automatically.").font(.footnote)
            }
        }.scrollContentBackground(.hidden).background(Finish.paper)
            .navigationTitle("Controls").navigationBarTitleDisplayMode(.inline)
    }
}

struct MateEyes:View {
    let resting:Bool
    let listening:Bool
    let thinking:Bool
    let focus:Double
    let verticalFocus:Double
    let reduceMotion:Bool
    var speaking=false
    var hearingSpeech=false
    @Environment(\.locale) private var locale
    var body:some View {
        let _ = locale.identifier
        Group {
            if resting || reduceMotion { eyes(blink:1,pulse:0) }
            else {
                TimelineView(.animation(minimumInterval:1.0/30)){timeline in
                    let time=timeline.date.timeIntervalSinceReferenceDate
                    let phase=time.truncatingRemainder(dividingBy:thinking ? 2.8:5.7)
                    eyes(blink:phase<0.16 ? max(0.08,abs(phase-0.08)/0.08):1.0,
                         pulse:speaking ? sin(time*2*Double.pi/0.7):0)
                }
            }
        }.animation(reduceMotion ? nil:.easeInOut(duration:0.25),value:resting)
    }
    private func eyes(blink:Double,pulse:Double)->some View {
            GeometryReader{g in
                let width=g.size.width*0.32
                let height=min(g.size.height*0.85,width*1.35)
                HStack(spacing:0){
                    ForEach(0..<2,id:\.self){index in
                        if resting {
                            Capsule().fill(Finish.ink).frame(width:width*0.75,height:4)
                                .frame(width:width,height:height)
                        } else {
                            Ellipse().fill(.white)
                                .overlay{Ellipse().strokeBorder(Finish.ink,lineWidth:3)}
                                .overlay{
                                    Ellipse().fill(Finish.ink)
                                        .frame(width:width*(hearingSpeech ? 0.25:0.20),height:height*(hearingSpeech ? 0.32:0.27))
                                        .offset(x:CGFloat(focus)*width*0.24+(index==0 ? width*0.08 : -width*0.08),
                                                y:CGFloat(verticalFocus)*height*0.24+(thinking ? -height*0.18:0))
                                }
                                .frame(width:width,height:height)
                                .scaleEffect(x:1,y:blink*(hearingSpeech ? 1.08:thinking ? 0.88:speaking ? 0.96+0.06*pulse:listening ? 0.96:0.92))
                            .animation(reduceMotion ? nil:.easeOut(duration:0.12),value:focus)
                            .animation(reduceMotion ? nil:.easeOut(duration:0.12),value:verticalFocus)
                            .animation(reduceMotion ? nil:.easeOut(duration:0.14),value:hearingSpeech)
                            .animation(reduceMotion ? nil:.easeOut(duration:0.18),value:thinking)
                        }
                    }
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
            }
    }
}

private struct SectionNote:View {
    let text:String
    @Environment(\.locale) private var locale
    var body:some View{Text(L10n.text(text,language:AppLanguage(rawValue:locale.identifier))).font(.system(size:13)).foregroundStyle(Finish.secondary).lineSpacing(4).fixedSize(horizontal:false,vertical:true)}
}
private struct PrimaryAction:View {
    let title:String
    var disabled=false
    let action:()->Void
    @Environment(\.locale) private var locale
    var body:some View {
        let _ = locale.identifier
        Button(action:action){Text(L10n.text(title)).font(.system(size:16,weight:.semibold)).frame(maxWidth:.infinity,minHeight:52)}
            .buttonStyle(.plain).foregroundStyle(Finish.paper).background(Finish.ink.opacity(disabled ? 0.35:1),in:RoundedRectangle(cornerRadius:16))
            .disabled(disabled)
    }
}

private struct ConversationSheet:View {
    @ObservedObject var model:CompanionModel
    @State private var input=""
    @Environment(\.locale) private var locale
    var body:some View {
        let _ = locale.identifier
        VStack(spacing:0){
            ScrollViewReader{proxy in
                ScrollView{
                    LazyVStack(alignment:.leading,spacing:26){
                        if model.messages.isEmpty {
                            VStack(alignment:.leading,spacing:12){
                                Text("Where shall we start?").font(.system(size:28,weight:.regular)).tracking(-0.7)
                                SectionNote(text:"This conversation stays on your iPhone. Before asking an external service, review the text and price.")
                            }.padding(.top,36)
                        }
                        ForEach(model.messages){message in
                            VStack(alignment:.leading,spacing:8){
                                Text(L10n.text(message.isUser ? "You":"Mate")).font(.system(size:11,weight:.semibold)).foregroundStyle(Finish.secondary)
                                Text(message.text).font(.system(size:17)).lineSpacing(5).textSelection(.enabled)
                            }.frame(maxWidth:.infinity,alignment:.leading).id(message.id)
                        }
                        if model.thinking{ProgressView("Thinking").font(.footnote)}
                    }.padding(26)
                }.onChange(of:model.messages.count){_,_ in if let id=model.messages.last?.id{withAnimation{proxy.scrollTo(id,anchor:.bottom)}}}
            }
            Divider().overlay(Finish.rule)
            HStack(alignment:.bottom,spacing:12){
                TextField("Message",text:$input,axis:.vertical).lineLimit(1...5).font(.system(size:17))
                    .accessibilityIdentifier("message-input")
                Button{let value=input;input="";model.send(value)}label:{Image(systemName:"arrow.up").font(.system(size:17,weight:.semibold)).frame(width:44,height:44).foregroundStyle(Finish.paper).background(Finish.ink,in:Circle())}
                    .disabled(input.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || model.thinking || model.financialBusy)
                    .accessibilityLabel("Send").accessibilityIdentifier("send-message")
            }.padding(.horizontal,22).padding(.vertical,14)
        }.background(Finish.paper).navigationTitle("Conversation").navigationBarTitleDisplayMode(.inline)
    }
}

private struct SettingsSheet:View {
    @ObservedObject var model:CompanionModel
    @ObservedObject var sensors:MateModel
    @AppStorage(L10n.preferenceKey) private var language = AppLanguage.english.rawValue
    @AppStorage(L10n.speechPreferenceKey) private var spokenLanguage = AppLanguage.japanese.rawValue
    @Environment(\.locale) private var locale
    var body:some View {
        let _ = locale.identifier
        Form{
            Section("Language"){
                Picker("App language",selection:$language){
                    ForEach(AppLanguage.allCases){Text(verbatim:$0.name).tag($0.rawValue)}
                }.pickerStyle(.segmented).accessibilityIdentifier("app-language")
                Picker("Spoken language",selection:$spokenLanguage){
                    ForEach(AppLanguage.allCases){Text(verbatim:$0.name).tag($0.rawValue)}
                }.pickerStyle(.segmented).accessibilityIdentifier("spoken-language")
                SectionNote(text:"Changing language rests Mate. Tap the resting face to resume.")
            }
            Section("Requests and evidence") {
                Button(L10n.text(UserDefaults.standard.string(forKey:model.setupCheckpointKey) == nil ? "Set up external requests":"Resume external request setup")){model.sheet = .setup}.accessibilityIdentifier("open-setup")
                Button("Try private rules on this device"){model.sheet = .localProof}.accessibilityIdentifier("open-local-proof")
                Button("Activity"){model.sheet = .activity}.accessibilityIdentifier("open-activity")
            }
            Section("Senses"){
                HStack{Label("Camera",systemImage:"eye");Spacer();Text(L10n.text(sensors.cameraPhase.rawValue)).font(.footnote).foregroundStyle(.secondary)}
                Button(L10n.text(sensors.captureRequested ? "Stop camera":sensors.isTransitioning ? "Waiting for camera to stop":"Start camera")){
                    if sensors.captureRequested{sensors.stopCapture()}else{sensors.startCapture()}
                }.disabled(!sensors.captureRequested && sensors.isTransitioning).accessibilityIdentifier("toggle-camera")
                SectionNote(text:"Detects broad object categories and face positions, not identity. Video is never saved or sent externally.")
                if let message=sensors.message{SectionNote(text:message)}
                if let message=sensors.dockMessage{SectionNote(text:message)}
                LabeledContent("Stand",value:L10n.text(!sensors.dockConnected ? "Not connected":!sensors.dockTrackingButtonEnabled ? "Enable tracking with the stand button":sensors.trackingEnabled != true ? "Start camera to enable tracking":sensors.dockTrackingSubjects>0 ? "Tracking a subject":"Looking for a subject"))
                Toggle("Read replies aloud",isOn:$model.readAloud)
            }
            Section("Delegation"){
                Button{model.sheet = .rules}label:{Label("Your rules",systemImage:"checkmark.shield")}
                Button{model.sheet = .wallet}label:{Label("Wallet",systemImage:"creditcard")}
                if model.configuration.chainID == 11_155_111, !model.configuration.ensParent.isEmpty {
                    Button{model.sheet = .identity}label:{Label("Mate's name",systemImage:"at")}
                }
                Button{model.makeDraft(service:.translation)}label:{Label("Request external translation",systemImage:"character.bubble")}
                Button{model.makeDraft(service:.summary)}label:{Label("Request external summary",systemImage:"text.alignleft")}
            }
            Section("Local notes"){
                TextField("What should Mate remember?",text:$model.localNotes,axis:.vertical).lineLimit(3...8)
                Button("Save notes"){model.saveNotes()}
                SectionNote(text:"Stored in this iPhone's Keychain. Never shared with external providers or published to ENS.")
            }
            Section("Connections"){
                Button("Configure connection"){model.sheet = .connection}.disabled(model.financialBusy)
                LabeledContent("Conversation",value:L10n.text(model.modelUnavailable == nil ? "On-device":"Check availability"))
                if let unavailable=model.modelUnavailable{SectionNote(text:unavailable)}
                LabeledContent("Payment network",value:L10n.text(model.configuration.networkName))
                LabeledContent("Wallet setup",value:L10n.text(model.configuration.walletConfigured ? "Configured":"Not configured"))
                LabeledContent("External execution setup",value:L10n.text(model.configuration.paymentsConfigured ? "Configured":"Not configured"))
                LabeledContent("On-device proving",value:L10n.text(model.proofUnavailable == nil ? "Available":"Unavailable"))
                if let reason=model.proofUnavailable{SectionNote(text:reason)}
                SectionNote(text:"ZK verifies private spending rules. Payment recipients and amounts are public. The current settlement design trusts the signature of the server that verifies the proof.")
            }
            Section{Button("Clear conversation",role:.destructive){model.clearConversation()}}
        }.scrollContentBackground(.hidden).background(Finish.paper).navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
    }
}

private struct SetupSheet:View {
    @ObservedObject var model:CompanionModel
    @ObservedObject var wallet:WalletService
    private var stage:SetupStage{model.setupProgress.stage}
    private var title:String {
        switch stage {
        case .restoring:return "Restore saved progress"
        case .recovery:return "Check the pending operation"
        case .connection:return "Connect your shop"
        case .login:return "Sign in to your wallet"
        case .wallets:return "Prepare your two wallets"
        case .account:return "Check your execution account"
        case .funds:return "Add test funds"
        case .rules:return "Choose what Mate may do"
        case .request:return "Make your first request"
        }
    }
    private var detail:String {
        switch stage {
        case .restoring:return "Mate is restoring saved operations. No registration or payment will be repeated."
        case .recovery:return "A previous operation needs confirmation. Recover it before changing connections or creating another order."
        case .connection:return "Verify your HTTPS service, test network and public Privy app IDs. Your existing connection stays in place until the new one passes."
        case .login:return "Sign in with your existing Privy account. This does not create a mandate or send funds."
        case .wallets:return "Your owner wallet approves permissions. Mate uses a separate execution key. Existing wallets are restored first."
        case .account:return "Refresh the current balance before continuing. A saved setup step is not evidence of available funds."
        case .funds:return "The execution account has no test USDC. In Wallet, review the amount, approve it, then deposit. Each transaction needs its own approval."
        case .rules:return "Review the services, spending limit and expiry. Only the displayed terms will be signed."
        case .request:return "The connection, wallet, balance and mandate have been checked. Choose a service and review the text and price before placing an order."
        }
    }
    var body:some View {
        Form {
            Section {
                Text(L10n.text(title)).font(.title2)
                Text(L10n.text(detail)).font(.body)
                LabeledContent("Test network",value:L10n.text(model.configuration.networkName))
                if let host=URL(string:model.configuration.apiURL)?.host{LabeledContent("Execution service",value:host)}
                if let date=model.accountCheckedAt{LabeledContent("Last checked",value:date.formatted())}
            }
            Section {
                if model.setupChecking || stage == .restoring {ProgressView("Checking setup…")}
                else {
                    switch stage {
                    case .connection:NavigationLink("Configure connection"){ConnectionSheet(model:model)}
                    case .login,.wallets,.funds:NavigationLink("Open wallet"){WalletSheet(model:model,wallet:wallet)}
                    case .rules:NavigationLink("Review your rules"){RulesSheet(model:model)}
                    case .account:Button("Refresh balances"){Task{await model.refreshSetup()}}
                    case .request:Button("Request external translation"){model.makeDraft(service:.translation)}
                    case .recovery:
                        if model.pendingExecution != nil {
                            Button("Check result"){Task{await model.recoverExecution();await model.refreshSetup()}}
                        } else {
                            Button("Recover pending mandate"){Task{await model.recoverGrant();await model.refreshSetup()}}
                        }
                    case .restoring:EmptyView()
                    }
                }
                if let message=model.setupMessage{Text(L10n.text(message)).foregroundStyle(.secondary)}
            }.disabled(model.financialBusy)
            Section {
                Text("Local conversation and private proof checks are available without this setup.").font(.footnote)
                Button("Do this later"){model.sheet=nil}
            }
        }.scrollContentBackground(.hidden).background(Finish.paper)
            .navigationTitle("Set up external requests").navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("setup-flow")
            .task{await model.refreshSetup()}
            .onChange(of:model.stateLoaded){_,loaded in if loaded{Task{await model.refreshSetup()}}}
    }
}

private struct RulesSheet:View {
    @ObservedObject var model:CompanionModel
    @State private var budget:String
    @State private var translation:Bool
    @State private var summary:Bool
    @State private var hours:Int
    @State private var exactExpiry:Date?
    @Environment(\.locale) private var locale
    init(model:CompanionModel) {
        self.model=model
        let draft=model.ruleDraft
        _budget=State(initialValue:draft.map{TokenAmount(units:$0.budgetUnits).display} ?? "5")
        _translation=State(initialValue:draft?.translation ?? true)
        _summary=State(initialValue:draft?.summary ?? true)
        _hours=State(initialValue:8)
        _exactExpiry=State(initialValue:draft?.validUntil)
    }
    var body:some View {
        let _ = locale.identifier
        Form{
            Section{
                Text("You set\nthe boundaries.").font(.system(size:29,weight:.regular)).tracking(-0.8).padding(.vertical,12)
                SectionNote(text:"Your budget and permissions stay on this device. The external execution service receives a proof that the request meets those rules.")
            }
            if let mandate=model.mandate {
                Section("Current mandate"){
                    LabeledContent("Spending limit",value:TokenAmount(units:mandate.policy.budget).display+" USDC")
                    LabeledContent("Spent",value:TokenAmount(units:model.spent).display+" USDC")
                    LabeledContent("Expires",value:Date(timeIntervalSince1970:Double(mandate.grant.validUntil)).formatted(.dateTime.year().month().day().hour().minute().locale(locale)))
                    Button("Refresh spending"){Task{await model.refreshAccount()}}
                    Button("Revoke this mandate",role:.destructive){Task{await model.fund(.revoke(mandate.id))}}.disabled(model.financialBusy)
                }
            }else{
                Section("New mandate"){
                    HStack{Text("Spending limit");Spacer();TextField("5",text:$budget).multilineTextAlignment(.trailing).keyboardType(.decimalPad);Text("USDC").foregroundStyle(.secondary)}
                    Toggle("Translation",isOn:$translation);Toggle("Summary",isOn:$summary)
                    if let expiry=exactExpiry {
                        DatePicker("Expires",selection:Binding(get:{exactExpiry ?? expiry},set:{exactExpiry=$0}),displayedComponents:[.date,.hourAndMinute])
                    } else {
                        Stepper("Valid for \(hours) hours",value:$hours,in:1...24)
                    }
                    SectionNote(text:"No limit increases, redelegation or arbitrary contract calls are allowed. Device authentication is required before signing.")
                    PrimaryAction(title:"Approve these terms",disabled:model.financialBusy || (!translation && !summary)){
                        Task{await model.authorize(budget:budget,translation:translation,summary:summary,hours:hours,validUntil:exactExpiry)}
                    }.listRowInsets(EdgeInsets(top:10,leading:0,bottom:10,trailing:0)).listRowBackground(Color.clear)
                }
                Section{Button("Recover pending mandate"){Task{await model.recoverGrant()}}}
            }
            if let status=model.executionStatus{Section{ProgressView(L10n.text(status))}}
        }.scrollContentBackground(.hidden).background(Finish.paper).navigationTitle("Your rules").navigationBarTitleDisplayMode(.inline)
            .task{model.clearRuleDraft();await model.refreshAccount()}
    }
}

private struct WalletSheet:View {
    @ObservedObject var model:CompanionModel
    @ObservedObject var wallet:WalletService
    @State private var email=""
    @State private var code=""
    @State private var codeSent=false
    @State private var amount="20"
    private func run(_ operation:@escaping () async throws -> Void){Task{do{try await operation()}catch{model.errorMessage=error.localizedDescription}}}
    @Environment(\.locale) private var locale
    var body:some View {
        let _ = locale.identifier
        Form{
            Section{SectionNote(text:L10n.format("%@ test USDC only. Do not send real funds. Your owner wallet and Mate's execution key are separate.",L10n.text(model.configuration.networkName)))}
            if !wallet.isAuthenticated {
                Section("Connect with Privy"){
                    TextField("Email address",text:$email).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    if codeSent {
                        TextField("Verification code",text:$code).keyboardType(.numberPad).textContentType(.oneTimeCode)
                        Button("Sign in"){run{try await wallet.login(email:email,code:code)}}.disabled(wallet.busy)
                    }else{Button("Send verification code"){run{try await wallet.sendCode(email:email);codeSent=true}}.disabled(wallet.busy || email.isEmpty)}
                }
            }
            if wallet.isAuthenticated && wallet.agentAddress == nil{
                Section{Button("Set up owner and Mate wallets"){run{try await wallet.prepareWallets();await model.refreshAccount()}}.disabled(wallet.busy)}
            }
            if let owner=wallet.ownerAddress {
                Section("Owner"){
                    Text(owner).font(.system(size:12,design:.monospaced)).textSelection(.enabled)
                    if let account=model.account {
                        LabeledContent("Wallet",value:TokenAmount(units:UInt64(account.tokenBalance) ?? 0).display+" USDC")
                        LabeledContent("Execution account",value:TokenAmount(units:UInt64(account.balance) ?? 0).display+" USDC")
                    }
                    Button("Refresh balances"){Task{await model.refreshAccount()}}
                }
                if let agent=wallet.agentAddress{Section("Mate's execution key"){Text(agent).font(.system(size:12,design:.monospaced)).textSelection(.enabled)}}
                Section("Manage funds"){
                    TextField("Amount (test USDC)",text:$amount).keyboardType(.decimalPad)
                    Button("1. Approve this deposit amount"){
                        do{let units=try TokenAmount(decimal:amount).units;Task{await model.fund(.approve(units))}}catch{model.errorMessage=error.localizedDescription}
                    }.disabled(model.financialBusy)
                    Button("2. Deposit into execution account"){
                        do{let units=try TokenAmount(decimal:amount).units;Task{await model.fund(.deposit(units))}}catch{model.errorMessage=error.localizedDescription}
                    }.disabled(model.financialBusy)
                    Button("Return to owner wallet"){
                        do{let units=try TokenAmount(decimal:amount).units;Task{await model.fund(.withdraw(units))}}catch{model.errorMessage=error.localizedDescription}
                    }.disabled(model.financialBusy)
                    SectionNote(text:"Deposits are public and separate from your private spending limit. For example, deposit 20 USDC and set a spending limit of 5 USDC.")
                }
            }
            if let status=model.executionStatus{Section{ProgressView(L10n.text(status))}}
        }.scrollContentBackground(.hidden).background(Finish.paper).navigationTitle("Wallet").navigationBarTitleDisplayMode(.inline)
            .task{await model.refreshAccount()}
    }
}

private struct IdentitySheet:View {
    @ObservedObject var model:CompanionModel
    @State private var label=""
    @Environment(\.locale) private var locale
    var body:some View {
        let _ = locale.identifier
        Form{
            Section{
                Text("Give your companion a name.").font(.system(size:29)).tracking(-0.8).padding(.vertical,12)
                SectionNote(text:"An ENSv2 subname points to Mate's address. Only the name, address and a short introduction are public.")
            }
            if let identity=model.identity {
                Section("Registered"){
                    Text(identity.name).font(.title3).textSelection(.enabled)
                    Text(identity.address).font(.system(size:12,design:.monospaced)).textSelection(.enabled)
                    SectionNote(text:identity.description)
                }
            }else{
                Section("New name"){
                    TextField("e.g. amedama",text:$label).textInputAutocapitalization(.never).autocorrectionDisabled()
                    if !model.configuration.ensParent.isEmpty{Text("\(label).\(model.configuration.ensParent)").font(.footnote)}
                    SectionNote(text:"Use 3–32 letters, digits or hyphens. You manage the name; it points to Mate's address.")
                    SectionNote(text:"Registration lasts one year. The parent domain administrator can also change or remove the name.")
                    Button("Sign and register name"){Task{await model.registerIdentity(label:label)}}.disabled(model.financialBusy || label.count<3 || model.configuration.ensParent.isEmpty)
                    if model.configuration.ensParent.isEmpty{SectionNote(text:"Configure the ENS parent domain before registering a name.")}
                }
            }
            Section{SectionNote(text:"A name does not prove trustworthiness or payment authority. Approval binds the resolved address and transaction details, not the name alone.")}
        }.scrollContentBackground(.hidden).background(Finish.paper).navigationTitle("Mate's name").navigationBarTitleDisplayMode(.inline)
    }
}

private struct DisclosureSheet:View {
    @ObservedObject var model:CompanionModel
    @State private var payload=""
    @State private var selectedID:String?
    private var selected:ServiceProvider?{model.providers.first{$0.id==selectedID}}
    @Environment(\.locale) private var locale
    var body:some View {
        let _ = locale.identifier
        Form{
            Section{
                Text("Only this text\nleaves your device.").font(.system(size:29)).tracking(-0.8).padding(.vertical,12)
                SectionNote(text:"This text is sent with the recipient, price, signature and proof. Conversation history, camera video, local notes and your total budget are not sent. Remove any unnecessary personal information.")
            }
            Section("Before a paid request") {
                if !model.configuration.paymentsConfigured {
                    SectionNote(text:"Connect to your execution service before making paid requests. Local ZK works without this connection.")
                    Button("Connect execution service"){model.sheet = .connection}
                } else if model.wallet.agentAddress == nil {
                    Button("1. Set up and fund your wallet") { model.sheet = .wallet }
                } else if model.mandate == nil {
                    Button("2. Approve your private spending rules") { model.sheet = .rules }
                    Button("Check wallet funds") { model.sheet = .wallet }
                } else {
                    Label("Spending mandate available",systemImage:"checkmark.shield")
                    SectionNote(text:"The current mandate and remaining allowance are checked again before proof generation.")
                }
            }
            Section("Text to share"){
                TextEditor(text:$payload).frame(minHeight:170).scrollContentBackground(.hidden).font(.body)
                    .accessibilityIdentifier("disclosure-text").disabled(model.financialBusy)
                    .onChange(of:payload){_,text in model.draft?.text=text}
            }
            Section("Provider"){
                if model.discovering{ProgressView("Searching live registrations")}
                ForEach(model.providers){provider in
                    Button{selectedID=provider.id}label:{
                        HStack(alignment:.top){
                            VStack(alignment:.leading,spacing:6){
                                Text(provider.name).font(.system(size:17,weight:.medium))
                                Text(provider.ensName).font(.footnote).foregroundStyle(.secondary)
                                Text("\(TokenAmount(units:UInt64(provider.price) ?? 0).display) USDC · \(provider.feedback) feedback entries").font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer();if selectedID==provider.id{Image(systemName:"checkmark")}
                        }.padding(.vertical,6)
                    }.disabled(model.financialBusy)
                }
                if let evidence=model.discoveryEvidence{SectionNote(text:evidence)}
                Button("Find providers"){if let draft=model.draft{Task{await model.findProviders(service:draft.service)}}}.disabled(model.discovering || model.financialBusy)
                SectionNote(text:"Candidates come from current registrations on The Graph. Feedback counts alone do not guarantee safety.")
            }
            if let selected {
                Section("Let Mate handle future requests") {
                    Text("Allow the text in future explicit requests to be sent to this shop without asking again. The signed mandate's total budget and expiry still apply.").font(.footnote)
                    Text("\(selected.name) · up to \(TokenAmount(units:UInt64(selected.price) ?? 0).display) test USDC per request")
                    Button("Authorize this shop and limit") {Task{await model.permitAgent(provider:selected)}}
                        .disabled(model.financialBusy || model.mandate == nil)
                }
                Section("Payment recipient"){
                    Text(selected.recipient).font(.system(size:12,design:.monospaced)).textSelection(.enabled)
                    SectionNote(text:"The proof and signature bind this address, price and text. The recipient cannot change after approval.")
                }
                Section{
                    PrimaryAction(title:model.financialBusy ? "Executing":"Send this text and request service",disabled:model.financialBusy || payload.isEmpty || model.mandate == nil){
                        let approvedPayload=payload
                        Task{await model.execute(payload:approvedPayload,provider:selected)}
                    }.listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                    if model.mandate == nil{SectionNote(text:"Complete the setup steps above, then return to review this saved request.")}
                }
            }
            if let status=model.executionStatus{Section{ProgressView(L10n.text(status))}}
        }.scrollContentBackground(.hidden).background(Finish.paper).navigationTitle(L10n.text(model.draft?.service.title ?? "External request")).navigationBarTitleDisplayMode(.inline)
            .onAppear{payload=model.draft?.text ?? ""}
            .interactiveDismissDisabled(model.financialBusy)
    }
}

private struct ActivitySheet:View {
    @ObservedObject var model:CompanionModel
    @Environment(\.locale) private var locale
    var body:some View {
        let _ = locale.identifier
        List{
            if let pending=model.pendingExecution {
                Section("Awaiting confirmation"){
                    SectionNote(text:"The result is not confirmed yet. If the service has not received the request, retry with the same saved signature and request ID. New payments are paused.")
                    Text(pending.actionHash).font(.system(size:11,design:.monospaced)).textSelection(.enabled)
                    Button("Check result"){Task{await model.recoverExecution()}}.disabled(model.financialBusy)
                    Button("Cancel if no payment was sent",role:.destructive){Task{await model.cancelPendingExecution()}}.disabled(model.financialBusy)
                }
            }
            if model.receipts.isEmpty {
                Section{
                    VStack(alignment:.leading,spacing:14){
                        Text("No executions yet.").font(.system(size:25)).tracking(-0.6)
                        SectionNote(text:"Only requests with a verified proof and confirmed testnet payment are recorded here.")
                    }.padding(.vertical,24)
                }.listRowBackground(Color.clear)
            }
            ForEach(model.receipts){receipt in
                Section("Confirmed execution"){
                    Text(receipt.result).font(.system(size:16)).lineSpacing(4).textSelection(.enabled)
                    LabeledContent("Total spent",value:TokenAmount(units:UInt64(receipt.spentAfter) ?? 0).display+" USDC")
                    Text("Proof SHA-256").font(.caption).foregroundStyle(.secondary)
                    Text(receipt.proofHash).font(.system(size:10,design:.monospaced)).textSelection(.enabled)
                    if let url=URL(string:model.configuration.explorerURL+"/tx/"+receipt.transactionHash){Link("View confirmed transaction",destination:url)}
                }
            }
        }.scrollContentBackground(.hidden).background(Finish.paper).navigationTitle("Activity").navigationBarTitleDisplayMode(.inline)
    }
}
