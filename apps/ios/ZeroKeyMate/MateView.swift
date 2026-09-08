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
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(L10n.preferenceKey) private var language = AppLanguage.english.rawValue
    @Environment(\.locale) private var locale
    var body:some View {
        let _ = locale.identifier
        CompanionHome(model:model,sensors:model.sensors,voice:model.voice)
            .task{model.setForeground(scenePhase == .active);await model.start()}
            .onChange(of:language){_,_ in model.rest();model.errorMessage=nil}
            .onChange(of:scenePhase){_,value in
                if value == .background{model.setForeground(false)}
                else if value == .active{model.setForeground(true)}
            }
            .sheet(item:$model.sheet){sheet in
                NavigationStack{
                    Group {
                        switch sheet {
                        case .controls:ControlsSheet(model:model,sensors:model.sensors,voice:model.voice)
                        case .conversation:ConversationSheet(model:model)
                        case .settings:SettingsSheet(model:model,sensors:model.sensors)
                        case .rules:RulesSheet(model:model)
                        case .wallet:WalletSheet(model:model,wallet:model.wallet)
                        case .identity:IdentitySheet(model:model)
                        case .activity:ActivitySheet(model:model)
                        case .disclosure:DisclosureSheet(model:model)
                        case .localProof:LocalProofSheet(proofs:model.proofs) { model.makeDraft(service:.translation) }
                        case .connection:ConnectionSheet(model:model)
                        }
                    }
                    .toolbar{ToolbarItem(placement:.topBarTrailing){Button("Close",systemImage:"xmark"){model.sheet=nil}.labelStyle(.iconOnly).accessibilityIdentifier("close-sheet")}}
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
    private var status:String {
        if let status=model.executionStatus{return status}
        if model.sleeping{return "Taking a rest."}
        if model.thinking{return "Thinking."}
        if voice.listening{return "Listening."}
        if voice.requestingPermission{return "Preparing voice input."}
        if voice.speaking{return "Speaking."}
        return "I'm here."
    }
    var body:some View {
        GeometryReader{geometry in
            MateEyes(resting:model.sleeping,listening:voice.listening,
                     thinking:model.thinking || model.financialBusy,
                     focus:sensors.horizontalFocus,verticalFocus:sensors.verticalFocus,reduceMotion:reduceMotion)
                .frame(width:min(geometry.size.width*0.78,620),height:min(geometry.size.height*0.38,300))
                .frame(maxWidth:.infinity,maxHeight:.infinity)
                .contentShape(Rectangle())
                .onTapGesture{model.sheet = .controls}
                .onLongPressGesture{model.rest()}
                .accessibilityElement(children:.ignore)
                .accessibilityLabel("Mate")
                .accessibilityValue(L10n.text(status))
                .accessibilityHint("Tap to open controls. Touch and hold to rest.")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction{model.sheet = .controls}
                .accessibilityAction(named:Text("Rest and stop camera and microphone")){model.rest()}
                .accessibilityIdentifier("companion-face")
        }.background(Finish.paper.ignoresSafeArea()).preferredColorScheme(.light).statusBarHidden()
    }
}

private struct ControlsSheet:View {
    @ObservedObject var model:CompanionModel
    @ObservedObject var sensors:MateModel
    @ObservedObject var voice:VoiceService
    var body:some View {
        Form {
            Section {
                Button("Start companion"){
                    model.sheet=nil
                    Task{await model.startCompanion()}
                }.disabled(model.financialBusy).accessibilityIdentifier("start-companion")
                SectionNote(text:"Start camera tracking and on-device voice conversation.")
                Button("Talk"){
                    model.sheet=nil
                    Task{await model.toggleVoice()}
                }.disabled(model.financialBusy).accessibilityIdentifier("talk-button")
                Button("Type a message"){model.sheet = .conversation}.accessibilityIdentifier("open-conversation")
                Button("Rest and stop camera and microphone") {model.rest();model.sheet=nil}
                    .accessibilityIdentifier("rest-button")
            }
            Section {
                Text(L10n.text(model.sleeping ? "Taking a rest.":"I'm here."))
                Text(L10n.text(sensors.cameraPhase == .on ? "Camera on · On-device processing":sensors.cameraPhase == .starting ? "Camera starting":sensors.cameraPhase == .stopping ? "Camera stopping":"Camera off"))
                    .accessibilityIdentifier("camera-status")
                if sensors.cameraPhase == .on {
                    Text(L10n.text(sensors.detectedFaces>0 ? "I can see a face.":"Looking for a face. Face the front camera."))
                }
                if let error=voice.errorMessage{SectionNote(text:error)}
                if let message=sensors.message{SectionNote(text:message)}
            }
            Section {
                Button("Settings"){model.sheet = .settings}.accessibilityIdentifier("open-settings")
                Button("Activity"){model.sheet = .activity}.accessibilityIdentifier("open-activity")
                Button("Try private rules on this device"){model.sheet = .localProof}.accessibilityIdentifier("open-local-proof")
                if let draft=model.draft {
                    Button(L10n.format("Review %@ request",L10n.text(draft.service.title))){model.sheet = .disclosure}
                }
            }
        }.scrollContentBackground(.hidden).background(Finish.paper)
            .navigationTitle("Controls").navigationBarTitleDisplayMode(.inline)
    }
}

private struct MateEyes:View {
    let resting:Bool
    let listening:Bool
    let thinking:Bool
    let focus:Double
    let verticalFocus:Double
    let reduceMotion:Bool
    @Environment(\.locale) private var locale
    var body:some View {
        let _ = locale.identifier
        TimelineView(.animation(minimumInterval:1.0/30,paused:reduceMotion || resting)){timeline in
            let time=timeline.date.timeIntervalSinceReferenceDate
            let phase=time.truncatingRemainder(dividingBy:11.3)
            // Two unhurried blinks with unequal spacing, without an idle gaze wander.
            let blinkDistance=min(abs(phase-2.7),abs(phase-8.9))
            let blink=reduceMotion ? 1.0:blinkDistance<0.15 ?
                0.08+0.92*(1-cos(.pi*blinkDistance/0.15))/2:1.0
            GeometryReader{g in
                let width=min(g.size.width*0.17,g.size.height*0.30)
                let height=width*(listening ? 1.24:thinking ? 1.10:1.18)
                let offset=CGFloat(focus)*g.size.width*0.085
                let vertical=CGFloat(verticalFocus)*g.size.height*0.075
                HStack(spacing:g.size.width*0.22){
                    ForEach(0..<2,id:\.self){_ in
                        ZStack {
                            if resting {
                                Path { path in
                                    path.move(to:CGPoint(x:0,y:height*0.45))
                                    path.addQuadCurve(to:CGPoint(x:width,y:height*0.45),
                                                     control:CGPoint(x:width/2,y:height*0.78))
                                }.stroke(Finish.ink,style:StrokeStyle(lineWidth:5,lineCap:.round))
                            } else {
                                Ellipse().fill(Finish.ink)
                                    .overlay(alignment:.topLeading) {
                                        Ellipse().fill(Finish.paper.opacity(0.8))
                                            .frame(width:width*0.18,height:width*0.20)
                                            .offset(x:width*0.24,y:height*0.20)
                                    }
                                    .scaleEffect(x:1,y:blink)
                            }
                        }
                        .frame(width:width,height:height)
                        .offset(x:resting ? 0:offset,y:resting ? 0:vertical)
                        .animation(reduceMotion ? nil:.easeOut(duration:0.24),value:focus)
                        .animation(reduceMotion ? nil:.easeOut(duration:0.24),value:verticalFocus)
                    }
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
            }
        }.animation(reduceMotion ? nil:.easeInOut(duration:0.3),value:resting)
            .animation(reduceMotion ? nil:.easeInOut(duration:0.3),value:listening)
            .animation(reduceMotion ? nil:.easeInOut(duration:0.3),value:thinking)
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
    @Environment(\.locale) private var locale
    var body:some View {
        let _ = locale.identifier
        Form{
            Section("Language"){
                Picker("App language",selection:$language){
                    ForEach(AppLanguage.allCases){Text(verbatim:$0.name).tag($0.rawValue)}
                }.pickerStyle(.segmented).accessibilityIdentifier("app-language")
                SectionNote(text:"Changing language stops voice and camera. Tap Talk or Start camera when you are ready to resume.")
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
                Toggle("Continuous conversation",isOn:$model.continuousConversation)
                SectionNote(text:"When enabled, tap Talk to resume on-device voice input after each reply. Stop, Rest, backgrounding the app or undocking ends the session.")
            }
            Section("Delegation"){
                Button("Try private rules on this device",systemImage:"checkmark.shield"){model.sheet = .localProof}
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
                SectionNote(text:"Voice input starts only when you tap Talk and is transcribed on-device. Tap again to cancel, even while permissions are being requested.")
                SectionNote(text:"ZK verifies private spending rules. Payment recipients and amounts are public. The current settlement design trusts the signature of the server that verifies the proof.")
            }
            Section{Button("Clear conversation",role:.destructive){model.clearConversation()}}
        }.scrollContentBackground(.hidden).background(Finish.paper).navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
    }
}

private struct RulesSheet:View {
    @ObservedObject var model:CompanionModel
    @State private var budget="5"
    @State private var translation=true
    @State private var summary=true
    @State private var hours=8
    @Environment(\.locale) private var locale
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
                    Stepper("Valid for \(hours) hours",value:$hours,in:1...24)
                    SectionNote(text:"No limit increases, redelegation or arbitrary contract calls are allowed. Device authentication is required before signing.")
                    PrimaryAction(title:"Approve these terms",disabled:model.financialBusy || (!translation && !summary)){
                        Task{await model.authorize(budget:budget,translation:translation,summary:summary,hours:hours)}
                    }.listRowInsets(EdgeInsets(top:10,leading:0,bottom:10,trailing:0)).listRowBackground(Color.clear)
                }
                Section{Button("Recover pending mandate"){Task{await model.recoverGrant()}}}
            }
            if let status=model.executionStatus{Section{ProgressView(L10n.text(status))}}
        }.scrollContentBackground(.hidden).background(Finish.paper).navigationTitle("Your rules").navigationBarTitleDisplayMode(.inline)
            .task{await model.refreshAccount()}
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
