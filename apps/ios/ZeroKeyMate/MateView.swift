import SwiftUI
import MateCore

enum Finish {
    static let paper=Color(red:0.958,green:0.954,blue:0.937)
    static let ink=Color(red:0.105,green:0.112,blue:0.112)
    static let secondary=Color(red:0.36,green:0.37,blue:0.36)
    static let rule=Color.black.opacity(0.10)
}

struct MateView:View {
    @StateObject private var model=CompanionModel()
    @Environment(\.scenePhase) private var scenePhase
    var body:some View {
        CompanionHome(model:model,sensors:model.sensors,voice:model.voice)
            .task{model.setForeground(scenePhase == .active);await model.start()}
            .onChange(of:scenePhase){_,value in
                if value == .background{model.setForeground(false)}
                else if value == .active{model.setForeground(true)}
            }
            .sheet(item:$model.sheet){sheet in
                NavigationStack{
                    Group {
                        switch sheet {
                        case .conversation:ConversationSheet(model:model)
                        case .settings:SettingsSheet(model:model,sensors:model.sensors)
                        case .rules:RulesSheet(model:model)
                        case .wallet:WalletSheet(model:model,wallet:model.wallet)
                        case .identity:IdentitySheet(model:model)
                        case .activity:ActivitySheet(model:model)
                        case .disclosure:DisclosureSheet(model:model)
                        case .proof:ProofInspectionView()
                        }
                    }
                    .toolbar{ToolbarItem(placement:.topBarTrailing){Button("閉じる",systemImage:"xmark"){model.sheet=nil}.labelStyle(.iconOnly).accessibilityIdentifier("close-sheet")}}
                    .toolbarBackground(Finish.paper,for:.navigationBar)
                }
                .tint(Finish.ink).presentationBackground(Finish.paper)
            }
            .alert("確認してください",isPresented:Binding(get:{model.errorMessage != nil},set:{if !$0{model.errorMessage=nil}})){
                Button("閉じる",role:.cancel){model.errorMessage=nil}
            }message:{Text(model.errorMessage ?? "")}
    }
}

private struct CompanionHome:View {
    @ObservedObject var model:CompanionModel
    @ObservedObject var sensors:MateModel
    @ObservedObject var voice:VoiceService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var status:String {
        if let status=model.executionStatus{return status}
        if model.sleeping{return "ひと休みしています。"}
        if model.thinking{return "考えています。"}
        if voice.listening{return "聞いています。"}
        if voice.requestingPermission{return "音声入力を準備しています。"}
        if voice.speaking{return "お話ししています。"}
        return "ここにいます。"
    }
    var body:some View {
        GeometryReader{geometry in
            let landscape=geometry.size.width>geometry.size.height
            VStack(spacing:0){
                HStack(alignment:.firstTextBaseline){
                    VStack(alignment:.leading,spacing:5){
                        Text("Mate.").accessibilityLabel("メイト").font(.system(size:32,weight:.medium,design:.rounded)).tracking(-1.2)
                        if let identity=model.identity{Text(identity.name).font(.system(size:11,weight:.medium)).foregroundStyle(Finish.secondary).lineLimit(1)}
                    }
                    Spacer(minLength:12)
                    Button{model.sheet = .activity}label:{Image(systemName:"clock").font(.system(size:19,weight:.regular)).frame(width:44,height:44)}
                        .accessibilityLabel("実行履歴").accessibilityIdentifier("open-activity")
                    Button{model.sheet = .settings}label:{Image(systemName:"slider.horizontal.3").font(.system(size:19,weight:.regular)).frame(width:44,height:44)}
                        .accessibilityLabel("設定").accessibilityIdentifier("open-settings")
                }.padding(.horizontal,landscape ? 40:28).padding(.top,landscape ? 8:18)
                Spacer(minLength:10)
                MateEyes(resting:model.sleeping,listening:voice.listening,thinking:model.thinking,
                         focus:sensors.horizontalFocus,reduceMotion:reduceMotion)
                    .frame(width:landscape ? min(geometry.size.width*0.34,310):geometry.size.width*0.67,
                           height:landscape ? min(geometry.size.height*0.30,140):min(geometry.size.height*0.25,185))
                    .accessibilityElement(children:.ignore).accessibilityLabel("Mateの表情").accessibilityValue(status)
                Spacer(minLength:landscape ? 8:24)
                VStack(spacing:10){
                    Text(status).font(.system(size:landscape ? 19:23,weight:.regular)).tracking(-0.4)
                        .multilineTextAlignment(.center).accessibilityIdentifier("companion-status")
                    if voice.listening,!voice.transcript.isEmpty {
                        Text(voice.transcript).font(.system(size:15)).foregroundStyle(Finish.secondary).lineLimit(2)
                    }else if let last=model.messages.last,!last.isUser,!landscape {
                        Text(last.text).font(.system(size:15)).foregroundStyle(Finish.secondary).multilineTextAlignment(.center).lineLimit(3)
                            .padding(.horizontal,12)
                    }
                    if let draft=model.draft,!model.financialBusy {
                        Button{model.sheet = .disclosure}label:{Label("\(draft.service.title)の依頼内容を確認",systemImage:"arrow.up.right").font(.system(size:14,weight:.medium)).padding(.vertical,10)}
                    }
                }.padding(.horizontal,30).frame(minHeight:landscape ? 42:112)
                Spacer(minLength:landscape ? 6:18)
                HStack(spacing:landscape ? 28:38){
                    Button{model.sheet = .conversation}label:{Image(systemName:"keyboard").font(.system(size:21,weight:.regular)).frame(width:52,height:52)}
                        .accessibilityLabel("文字で話す").accessibilityIdentifier("open-conversation")
                    Button{
                        if model.sleeping{model.wake()}else{Task{await model.toggleVoice()}}
                    }label:{
                        Image(systemName:model.sleeping ? "sun.max":voice.listening ? "stop.fill":"mic.fill")
                            .font(.system(size:25,weight:.medium)).foregroundStyle(Finish.paper)
                            .frame(width:76,height:76).background(Finish.ink,in:Circle())
                    }.disabled(model.thinking || model.financialBusy || voice.requestingPermission)
                        .accessibilityLabel(model.sleeping ? "Mateを起こす":voice.listening ? "音声入力を終了":"話す")
                        .accessibilityIdentifier("talk-button")
                    Button{model.rest()}label:{Image(systemName:"moon").font(.system(size:21,weight:.regular)).frame(width:52,height:52)}
                        .accessibilityLabel("カメラとマイクを停止して休む").accessibilityIdentifier("rest-button")
                }
                HStack(spacing:7){
                    Image(systemName:sensors.cameraPhase == .on ? "eye":"eye.slash").font(.system(size:11))
                    Text(sensors.cameraPhase == .on ? "カメラ使用中・端末内処理":sensors.isTransitioning ? "カメラを切り替え中":"カメラ停止中")
                    if sensors.dockConnected{Text("·");Text("Dock 接続済み")}
                }.font(.system(size:11,weight:.medium)).foregroundStyle(Finish.secondary)
                    .padding(.top,landscape ? 10:21).padding(.bottom,landscape ? 8:18)
                if let error=voice.errorMessage{Text(error).font(.footnote).foregroundStyle(Finish.secondary).padding(.horizontal,24).padding(.bottom,8)}
            }.frame(maxWidth:.infinity,maxHeight:.infinity).foregroundStyle(Finish.ink)
        }.background(Finish.paper.ignoresSafeArea()).preferredColorScheme(.light)
    }
}

private struct MateEyes:View {
    let resting:Bool
    let listening:Bool
    let thinking:Bool
    let focus:Double
    let reduceMotion:Bool
    var body:some View {
        TimelineView(.animation(minimumInterval:1.0/30,paused:reduceMotion || resting)){timeline in
            let time=timeline.date.timeIntervalSinceReferenceDate
            let phase=time.truncatingRemainder(dividingBy:5.7)
            let blink=reduceMotion ? 1.0:phase<0.16 ? max(0.08,abs(phase-0.08)/0.08):1.0
            GeometryReader{g in
                let width=g.size.width*0.21
                let height=resting ? 5.0:g.size.height*(listening ? 0.73:0.65)
                let offset=reduceMotion ? 0:CGFloat(focus)*10
                HStack(spacing:g.size.width*0.24){
                    ForEach(0..<2,id:\.self){index in
                        RoundedRectangle(cornerRadius:width/2,style:.continuous)
                            .fill(Finish.ink)
                            .frame(width:width,height:max(5,height*blink*(thinking && index==1 ? 0.70:1)))
                            .offset(x:offset,y:thinking && index==1 ? -8:0)
                    }
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
            }
        }.animation(reduceMotion ? nil:.easeInOut(duration:0.25),value:resting)
    }
}

private struct SectionNote:View {
    let text:String
    var body:some View{Text(text).font(.subheadline).foregroundStyle(Finish.secondary).lineSpacing(4).fixedSize(horizontal:false,vertical:true)}
}
private struct PrimaryAction:View {
    let title:String
    var disabled=false
    let action:()->Void
    var body:some View {
        Button(action:action){Text(title).font(.system(size:16,weight:.semibold)).frame(maxWidth:.infinity,minHeight:52)}
            .buttonStyle(.plain).foregroundStyle(Finish.paper).background(Finish.ink.opacity(disabled ? 0.35:1),in:RoundedRectangle(cornerRadius:16))
            .disabled(disabled)
    }
}

private struct ConversationSheet:View {
    @ObservedObject var model:CompanionModel
    @State private var input=""
    var body:some View {
        VStack(spacing:0){
            ScrollViewReader{proxy in
                ScrollView{
                    LazyVStack(alignment:.leading,spacing:26){
                        if model.messages.isEmpty {
                            VStack(alignment:.leading,spacing:12){
                                Text("何から始めましょう。").font(.system(size:28,weight:.regular)).tracking(-0.7)
                                SectionNote(text:"この会話はiPhoneの中で処理されます。外に仕事を頼むときは、送る文章と料金を先に確認します。")
                            }.padding(.top,36)
                        }
                        ForEach(model.messages){message in
                            VStack(alignment:.leading,spacing:8){
                                Text(message.isUser ? "あなた":"Mate").font(.system(size:11,weight:.semibold)).foregroundStyle(Finish.secondary)
                                Text(message.text).font(.system(size:17)).lineSpacing(5).textSelection(.enabled)
                            }.frame(maxWidth:.infinity,alignment:.leading).id(message.id)
                        }
                        if model.thinking{ProgressView("考えています").font(.footnote)}
                    }.padding(26)
                }.onChange(of:model.messages.count){_,_ in if let id=model.messages.last?.id{withAnimation{proxy.scrollTo(id,anchor:.bottom)}}}
            }
            Divider().overlay(Finish.rule)
            HStack(alignment:.bottom,spacing:12){
                TextField("メッセージ",text:$input,axis:.vertical).lineLimit(1...5).font(.system(size:17))
                    .accessibilityIdentifier("message-input")
                Button{let value=input;input="";model.send(value)}label:{Image(systemName:"arrow.up").font(.system(size:17,weight:.semibold)).frame(width:44,height:44).foregroundStyle(Finish.paper).background(Finish.ink,in:Circle())}
                    .disabled(input.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || model.thinking || model.financialBusy)
                    .accessibilityLabel("送信").accessibilityIdentifier("send-message")
            }.padding(.horizontal,22).padding(.vertical,14)
        }.background(Finish.paper).navigationTitle("会話").navigationBarTitleDisplayMode(.inline)
    }
}

private struct SettingsSheet:View {
    @ObservedObject var model:CompanionModel
    @ObservedObject var sensors:MateModel
    var body:some View {
        Form{
            Section {
                Button { model.sheet = .proof } label: { Label("証明を確かめる", systemImage:"checkmark.seal") }
                    .accessibilityIdentifier("open-proof-inspection")
                SectionNote(text:"実際のZK証明を端末内で生成・検証します。ログインや支払いは不要です。")
            }
            Section("感覚"){
                HStack{Label("カメラ",systemImage:"eye");Spacer();Text(sensors.cameraPhase.rawValue).font(.footnote).foregroundStyle(.secondary)}
                Button(sensors.captureRequested ? "カメラを停止":"カメラを開始"){
                    if sensors.captureRequested{sensors.stopCapture()}else{sensors.startCapture()}
                }.accessibilityIdentifier("toggle-camera")
                SectionNote(text:"認識するのは物体の大まかな分類と顔の位置です。本人特定は行いません。映像は保存・外部送信しません。")
                if let message=sensors.message{SectionNote(text:message)}
                if let message=sensors.dockMessage{SectionNote(text:message)}
                Toggle("返答を読み上げる",isOn:$model.readAloud)
            }
            Section("任せること"){
                Button{model.sheet = .rules}label:{Label("あなたのルール",systemImage:"checkmark.shield")}
                Button{model.sheet = .wallet}label:{Label("ウォレット",systemImage:"creditcard")}
                Button{model.sheet = .identity}label:{Label("Mateの名前",systemImage:"at")}
                Button{model.makeDraft(service:.translation)}label:{Label("外部に翻訳を依頼",systemImage:"character.bubble")}
                Button{model.makeDraft(service:.summary)}label:{Label("外部に要約を依頼",systemImage:"text.alignleft")}
            }
            Section("端末内のメモ"){
                TextField("覚えておいてほしいこと",text:$model.localNotes,axis:.vertical).lineLimit(3...8)
                Button("メモを保存"){model.saveNotes()}
                SectionNote(text:"このiPhoneのKeychainに保存します。外部の提供者やENSには公開しません。")
            }
            Section("接続"){
                LabeledContent("会話",value:model.modelUnavailable == nil ? "オンデバイス":"利用条件を確認")
                if let unavailable=model.modelUnavailable{SectionNote(text:unavailable)}
                LabeledContent("決済ネットワーク",value:"Sepolia テストネット")
                LabeledContent("ウォレット設定",value:model.configuration.walletConfigured ? "設定済み":"未設定")
                LabeledContent("外部実行の設定",value:model.configuration.paymentsConfigured ? "設定済み":"未設定")
                SectionNote(text:"ZKは非公開の利用条件を検証します。送金先・金額は公開されます。現在の決済方式は、証明を検証するサーバーの署名を信頼します。")
            }
            Section{Button("会話を消去",role:.destructive){model.clearConversation()}}
        }.scrollContentBackground(.hidden).background(Finish.paper).navigationTitle("設定").navigationBarTitleDisplayMode(.inline)
    }
}

private struct RulesSheet:View {
    @ObservedObject var model:CompanionModel
    @State private var budget="5"
    @State private var translation=true
    @State private var summary=true
    @State private var hours=8
    var body:some View {
        Form{
            Section{
                Text("任せる範囲を、\nあなたが決める。").font(.system(size:29,weight:.regular)).tracking(-0.8).padding(.vertical,12)
                SectionNote(text:"予算と許可条件はこの端末に残します。外部の実行サービスには、その条件を満たした証明だけを渡します。")
            }
            if let mandate=model.mandate {
                Section("現在の委任"){
                    LabeledContent("利用上限",value:TokenAmount(units:mandate.policy.budget).display+" USDC")
                    LabeledContent("利用済み",value:TokenAmount(units:model.spent).display+" USDC")
                    LabeledContent("期限",value:Date(timeIntervalSince1970:Double(mandate.grant.validUntil)).formatted(date:.abbreviated,time:.shortened))
                    Button("利用状態を更新"){Task{await model.refreshAccount()}}
                    Button("この委任を失効",role:.destructive){Task{await model.fund(.revoke(mandate.id))}}.disabled(model.financialBusy)
                }
            }else{
                Section("新しい委任"){
                    HStack{Text("利用上限");Spacer();TextField("5",text:$budget).multilineTextAlignment(.trailing).keyboardType(.decimalPad);Text("USDC").foregroundStyle(.secondary)}
                    Toggle("翻訳",isOn:$translation);Toggle("要約",isOn:$summary)
                    Stepper("有効期間 \(hours)時間",value:$hours,in:1...24)
                    SectionNote(text:"上限の増額・再委任・任意のコントラクト操作は許可しません。署名前に、端末の本人認証を行います。")
                    PrimaryAction(title:"この条件で承認",disabled:model.financialBusy || (!translation && !summary)){
                        Task{await model.authorize(budget:budget,translation:translation,summary:summary,hours:hours)}
                    }.listRowInsets(EdgeInsets(top:10,leading:0,bottom:10,trailing:0)).listRowBackground(Color.clear)
                }
                Section {
                    Button("確認待ちの委任を復元") { Task { await model.recoverGrant() } }
                    Button("期限切れが確定した承認を破棄") { Task { await model.retireExpiredGrant() } }
                }
            }
            if let status=model.executionStatus{Section{ProgressView(status)}}
        }.disabled(model.financialBusy).scrollContentBackground(.hidden).background(Finish.paper).navigationTitle("あなたのルール").navigationBarTitleDisplayMode(.inline)
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
    var body:some View {
        Form{
            Section{SectionNote(text:"SepoliaのテストUSDCのみを扱います。実際のお金は送らないでください。所有者のウォレットと、Mateの実行キーを分けます。")}
            if !wallet.isAuthenticated {
                Section("Privyで接続"){
                    TextField("メールアドレス",text:$email).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    if codeSent {
                        TextField("確認コード",text:$code).keyboardType(.numberPad).textContentType(.oneTimeCode)
                        Button("ログイン"){run{try await wallet.login(email:email,code:code)}}.disabled(wallet.busy)
                    }else{Button("確認コードを送る"){run{try await wallet.sendCode(email:email);codeSent=true}}.disabled(wallet.busy || email.isEmpty)}
                }
            }
            if wallet.isAuthenticated && wallet.agentAddress == nil{
                Section{Button("所有者とMateのウォレットを準備"){run{try await wallet.prepareWallets();await model.refreshAccount()}}.disabled(wallet.busy)}
            }
            if let owner=wallet.ownerAddress {
                Section("所有者"){
                    Text(owner).font(.system(size:12,design:.monospaced)).textSelection(.enabled)
                    if let account=model.account {
                        LabeledContent("ウォレット",value:(UInt64(account.tokenBalance).map { TokenAmount(units:$0).display } ?? "確認できません")+" USDC")
                        LabeledContent("実行用口座",value:(UInt64(account.balance).map { TokenAmount(units:$0).display } ?? "確認できません")+" USDC")
                    }
                    Button("残高を確認"){Task{await model.refreshAccount()}}
                }
                if let agent=wallet.agentAddress{Section("Mateの実行キー"){Text(agent).font(.system(size:12,design:.monospaced)).textSelection(.enabled)}}
                Section("資金の管理"){
                    TextField("金額（テストUSDC）",text:$amount).keyboardType(.decimalPad)
                    Button("1. この金額の預け入れを承認"){
                        do{let units=try TokenAmount(decimal:amount).units;Task{await model.fund(.approve(units))}}catch{model.errorMessage=error.localizedDescription}
                    }.disabled(model.financialBusy)
                    Button("2. 実行用口座に預ける"){
                        do{let units=try TokenAmount(decimal:amount).units;Task{await model.fund(.deposit(units))}}catch{model.errorMessage=error.localizedDescription}
                    }.disabled(model.financialBusy)
                    Button("所有者のウォレットに戻す"){
                        do{let units=try TokenAmount(decimal:amount).units;Task{await model.fund(.withdraw(units))}}catch{model.errorMessage=error.localizedDescription}
                    }.disabled(model.financialBusy)
                    SectionNote(text:"預け入れ額は公開されます。秘密にしたい利用上限とは別です。例えば20 USDCを預け、利用条件を5 USDCまでに設定します。")
                }
            }
            if let status=model.executionStatus{Section{ProgressView(status)}}
        }.disabled(model.financialBusy).scrollContentBackground(.hidden).background(Finish.paper).navigationTitle("ウォレット").navigationBarTitleDisplayMode(.inline)
            .task{await model.refreshAccount()}
    }
}

private struct IdentitySheet:View {
    @ObservedObject var model:CompanionModel
    @State private var label=""
    @State private var avatarURL=""
    var body:some View {
        Form{
            Section{
                Text("相棒にも、名前を。").font(.system(size:29)).tracking(-0.8).padding(.vertical,12)
                SectionNote(text:"ENSv2のサブネームから、Mateのアドレスを参照できます。公開するのは名前とアドレス、短い紹介だけです。")
            }
            if let identity=model.identity {
                Section("登録済み"){
                    Text(identity.name).font(.title3).textSelection(.enabled)
                    Text(identity.address).font(.system(size:12,design:.monospaced)).textSelection(.enabled)
                    SectionNote(text:identity.description)
                    Button("チェーンから名前を再確認") { Task { await model.refreshIdentity() } }
                }
                Section("Mateに任せる公開情報") {
                    TextField("アイコン画像のHTTPS URL",text:$avatarURL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Mateのキーでアイコンだけを更新") { Task { await model.updateAvatar(avatarURL) } }
                        .disabled(model.financialBusy || model.pendingWalletOperation != nil || avatarURL.isEmpty)
                    Button("アイコンの編集権限を取り消す",role:.destructive) { Task { await model.setAvatarPermission(false) } }
                        .disabled(model.financialBusy || model.pendingWalletOperation != nil)
                    Button("アイコンの編集権限を再び許可") { Task { await model.setAvatarPermission(true) } }
                        .disabled(model.financialBusy || model.pendingWalletOperation != nil)
                    SectionNote(text:"アドレスや所有者の変更権限は与えません。編集には実行キー側にもガス用のSepolia ETHが必要です。画像URLは公開されます。")
                    if let current=identity.avatar,!current.isEmpty { Text(current).font(.footnote).textSelection(.enabled) }
                }
            }else{
                Section("新しい名前"){
                    TextField("例 amedama",text:$label).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SectionNote(text:"半角英数字とハイフン、3〜32文字。名前の管理者はあなた、名前が指すアドレスはMateです。")
                    Button("署名して名前を登録"){Task{await model.registerIdentity(label:label)}}.disabled(model.financialBusy || label.count<3)
                }
            }
            Section{SectionNote(text:"名前は信頼性や支払権限の証明ではありません。支払いは名前ではなく、確定したアドレスと取引内容に結び付けて承認します。")}
        }.disabled(model.financialBusy).scrollContentBackground(.hidden).background(Finish.paper).navigationTitle("Mateの名前").navigationBarTitleDisplayMode(.inline)
    }
}

private struct DisclosureSheet:View {
    @ObservedObject var model:CompanionModel
    @State private var payload=""
    @State private var selectedID:String?
    private var selected:ServiceProvider?{model.providers.first{$0.id==selectedID}}
    var body:some View {
        Form{
            Section{
                Text("外に送るのは、\nこの文章だけ。").font(.system(size:29)).tracking(-0.8).padding(.vertical,12)
                SectionNote(text:"会話の続きやカメラ映像、端末内のメモ、予算の全体は送信しません。文章に不要な個人情報がないか確認してください。")
            }
            Section("送信する文章"){
                TextEditor(text:$payload).frame(minHeight:170).scrollContentBackground(.hidden).font(.body)
                    .accessibilityIdentifier("disclosure-text")
            }
            Section("提供者"){
                if model.discovering{ProgressView("ライブデータから探しています")}
                ForEach(model.providers){provider in
                    Button{selectedID=provider.id}label:{
                        HStack(alignment:.top){
                            VStack(alignment:.leading,spacing:6){
                                Text(provider.name).font(.system(size:17,weight:.medium))
                                Text(provider.ensName).font(.footnote).foregroundStyle(.secondary)
                                Text("\((UInt64(provider.price).map { TokenAmount(units:$0).display } ?? "確認できません")) USDC · フィードバック \(provider.feedback)件").font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer();if selectedID==provider.id{Image(systemName:"checkmark")}
                        }.padding(.vertical,6)
                    }
                }
                if let evidence=model.discoveryEvidence{SectionNote(text:evidence)}
                Button("提供者を検索"){if let draft=model.draft{Task{await model.findProviders(service:draft.service)}}}.disabled(model.discovering || model.financialBusy)
                SectionNote(text:"候補はThe Graphの最新の登録情報から取得します。評価件数だけで安全性を保証するものではありません。")
            }
            if let selected {
                Section("支払先"){
                    Text(selected.recipient).font(.system(size:12,design:.monospaced)).textSelection(.enabled)
                    SectionNote(text:"このアドレス・料金・文章を証明と署名に結び付けます。確認後の宛先変更は認めません。")
                }
                Section{
                    PrimaryAction(title:model.financialBusy ? "実行中":"この内容だけを送り、依頼する",disabled:model.financialBusy || payload.isEmpty || model.mandate == nil){
                        let approvedPayload=payload
                        Task{await model.execute(payload:approvedPayload,provider:selected)}
                    }.listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                    if model.mandate == nil{SectionNote(text:"先に「あなたのルール」で委任を承認してください。")}
                }
            }
            if let status=model.executionStatus{Section{ProgressView(status)}}
        }.disabled(model.financialBusy).scrollContentBackground(.hidden).background(Finish.paper).navigationTitle(model.draft?.service.title ?? "外部への依頼").navigationBarTitleDisplayMode(.inline)
            .onAppear{payload=model.draft?.text ?? ""}
            .interactiveDismissDisabled(model.financialBusy)
    }
}

private struct ActivitySheet:View {
    @ObservedObject var model:CompanionModel
    var body:some View {
        List{
            if let pending=model.pendingWalletOperation {
                Section("ウォレット操作の確認待ち") {
                    Text(pending.title)
                    Text(pending.hash).font(.system(.caption,design:.monospaced)).textSelection(.enabled)
                    Button("同じ署名済み取引を復旧") { Task { await model.recoverWalletOperation() } }.disabled(model.financialBusy)
                    SectionNote(text:"新たに署名せず、同じ取引を照会・再送します。新しいnonceや別の送金は作りません。")
                }
            }
            if let pending=model.pendingExecution {
                Section("結果の確認待ち"){
                    SectionNote(text:"送信後の結果がまだ確定していません。新しい支払いは停止しています。新しい依頼を作らず、同じ識別子で照会・復旧してください。")
                    Text(pending.actionHash).font(.system(size:11,design:.monospaced)).textSelection(.enabled)
                    Button("結果を照会・復旧"){Task{await model.recoverExecution()}}.disabled(model.financialBusy)
                    Button("期限切れと未実行を確認して閉じる") { Task { await model.retirePendingExecution() } }.disabled(model.financialBusy)
                }
            }
            if model.receipts.isEmpty {
                Section{
                    VStack(alignment:.leading,spacing:14){
                        Text("まだ、何も実行していません。").font(.system(size:25)).tracking(-0.6)
                        SectionNote(text:"証明を検証し、Sepoliaで支払いが確定した依頼だけを、ここに記録します。")
                    }.padding(.vertical,24)
                }.listRowBackground(Color.clear)
            }
            ForEach(model.receipts){receipt in
                Section("確認済みの実行"){
                    Text(receipt.result).font(.system(size:16)).lineSpacing(4).textSelection(.enabled)
                    LabeledContent("累積利用",value:(UInt64(receipt.spentAfter).map { TokenAmount(units:$0).display } ?? "確認できません")+" USDC")
                    Text("証明 SHA-256").font(.caption).foregroundStyle(.secondary)
                    Text(receipt.proofHash).font(.system(size:10,design:.monospaced)).textSelection(.enabled)
                    if let url=URL(string:"https://sepolia.etherscan.io/tx/"+receipt.transactionHash){Link("Sepoliaの取引を確認",destination:url)}
                }
            }
        }.scrollContentBackground(.hidden).background(Finish.paper).navigationTitle("実行履歴").navigationBarTitleDisplayMode(.inline)
    }
}
