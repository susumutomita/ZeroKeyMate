import AVFoundation
import Combine
import Foundation
import MateCore
import LocalAuthentication
import SwiftUI

struct ConversationMessage:Identifiable,Sendable {
    let id=UUID()
    let isUser:Bool
    let text:String
}
struct DisclosureDraft:Identifiable,Sendable {
    let id=UUID()
    let service:MateService
    var text:String
}
/// A brief, confirmed-result signal for the eyes: a short nod on a verified success,
/// a short shake on a verified rejection or failure. Never set from an animation
/// finishing; only from the actual state that produced the outcome.
typealias ExecutionOutcome = CompanionOutcome
struct PendingGrant:Codable,Sendable {
    let grant:MandateGrant
    let policy:PrivatePolicy
    let signature:String
}
struct PendingExecution:Codable,Sendable {
    let actionHash:String
    let proofHash:String
    let createdAt:Date
    var submission:ExecutionSubmission? = nil
}
/// A spoken revoke request awaiting the same "yes" confirmation window as an
/// agent offer. Confirming still goes through the existing signed revoke call.
private struct PendingRevoke {
    let mandateID:String
    let generation:UUID
    let createdAt:Date
    func accepts(_ input:String,generation:UUID,now:Date=Date())->Bool {
        let answer=input.lowercased().filter{!$0.isWhitespace && !$0.isPunctuation}
        return self.generation==generation && (0...60).contains(now.timeIntervalSince(createdAt)) &&
            ["はい","お願いします","お願い","進めて","yes","confirm","goahead"].contains(answer)
    }
}

@MainActor
final class CompanionModel:ObservableObject {
    enum Sheet:String,Identifiable {case welcome,controls,conversation,settings,setup,rules,wallet,identity,activity,disclosure,localProof,connection,cardAge,shop;var id:String{rawValue}}
    @Published var sheet:Sheet? {
        didSet {
            if financialBusy && oldValue != nil && oldValue != sheet { requestGeneration=UUID() }
            if sheet == .shop {
                // A purchase pauses speech input before a PIN can be entered.
                // Existing explicit camera consent remains under sensor control.
                stopVoice(); cancelConversation(); requestGeneration = UUID(); sleeping = false
            } else if let sheet,sheet != .conversation && sheet != .controls {
                rest()
                // Opening an explicit request screen is a new user interaction, not
                // sensor consent. Existing approval guards still require an awake app.
                if [.setup,.rules,.wallet,.identity,.disclosure,.localProof,.connection].contains(sheet){sleeping=false}
            }
            updateStandApproval()
        }
    }
    @Published var errorMessage:String? { didSet { if errorMessage != nil { stopVoice() } } }
    @Published private(set) var messages:[ConversationMessage]=[]
    @Published private(set) var thinking=false
    @Published private(set) var financialBusy=false
    @Published private(set) var executionStatus:String? {didSet{if executionStatus == nil{executionActivity=nil}}}
    @Published private(set) var executionActivity:CompanionActivity? {didSet{updateStandApproval()}}
    private func updateStandApproval() {
        sensors.setApprovalPending(executionActivity == .approval || agentOffer != nil || revokeOffer != nil || sheet == .disclosure || sheet == .rules || sheet == .shop)
    }
    var activity:CompanionActivity {
        let approval=agentOffer != nil || revokeOffer != nil || sheet == .disclosure || sheet == .rules || sheet == .shop
        return .resolve(resting:sleeping || (isResting && !approval && pendingExecution == nil && executionStatus == nil),
            operation:executionActivity ?? (financialBusy || executionStatus != nil ? .thinking:nil),
            pending:pendingExecution != nil,outcome:lastOutcome,approval:approval,
            speaking:voice.speaking,listening:voice.listening,thinking:thinking)
    }
    private func reportExecution(_ activity:CompanionActivity,_ text:String) {
        executionActivity=activity;executionStatus=text
    }
    @Published private(set) var modelUnavailable:String?
    @Published private(set) var proofUnavailable:String? = "Checking proof runtime."
    @Published private(set) var mandate:StoredMandate?
    @Published private(set) var agentDelegation:AgentDelegation?
    @Published private(set) var spent:UInt64=0
    @Published private(set) var account:AccountState?
    @Published private(set) var identity:MateIdentity?
    @Published private(set) var receipts:[ExecutionReceipt]=[]
    @Published private(set) var providers:[ServiceProvider]=[]
    @Published private(set) var discoveryEvidence:String?
    @Published private(set) var discovering=false
    @Published private(set) var lastProofMilliseconds:Int?
    @Published private(set) var pendingExecution:PendingExecution?
    @Published private(set) var lastOutcome:ExecutionOutcome?
    private var outcomeTask:Task<Void,Never>?
    @Published var draft:DisclosureDraft? { didSet { requestGeneration = UUID() } }
    var requestNeedsSetup:Bool {
        !stateLoaded || !configuration.paymentsConfigured || wallet.ownerAddress == nil || wallet.agentAddress == nil || mandate == nil
    }
    /// Keep only the unapproved text across setup. Quotes, signatures and offers
    /// must be obtained again in the newly selected environment.
    func continueRequest() {
        guard draft != nil,!thinking,!financialBusy else{return}
        sheet = pendingExecution != nil ? .activity : requestNeedsSetup ? .setup : .disclosure
    }
    func discardRequest() {
        guard !thinking,!financialBusy,pendingExecution == nil else{return}
        agentOffer=nil;draft=nil;providers=[];discoveryEvidence=nil
    }
    @Published private(set) var ruleDraft:RuleProposal?
    @Published var localNotes=""
    @Published var readAloud=true
    @Published var continuousConversation=false {
        didSet{if !continuousConversation{stopVoice()}}
    }
    @Published private var listeningSession=CompanionListeningSession()
    var voiceSessionActive:Bool{listeningSession.isActive}
    @Published private(set) var awaitingGreeting=false
    private var recognitionLocale:String?
    @Published var sleeping=true
    @Published private(set) var preparingCompanion=false
    var isResting:Bool {
        guard sensors.cameraPhase == .off else{return false}
        return sleeping || (!preparingCompanion && !voiceSessionActive && !voice.listening && !voice.speaking &&
                     !thinking && !financialBusy && !sensors.captureRequested && sensors.cameraPhase == .off)
    }
    @Published private(set) var configuration:AppConfiguration
    let sensors=MateModel()
    let voice=VoiceService()
    @Published private(set) var wallet:WalletService
    private let planner:any AgentPlanning
    private let shopPlanner = ShopPlanner()
    private var shopReplyLanguage = AppLanguage.english
    private var agentOffer:AgentOffer? {didSet{updateStandApproval()}}
    private let conversation:any ConversationResponding
    // A single actor serializes native work across payment and offline screens.
    let proofs=ProofService()
    private var network:NetworkService
    private var rpc:EthereumRPC
    private var conversationTask:Task<Void,Never>?
    private var conversationGeneration:UInt64=0
    private var revokeOffer:PendingRevoke? {didSet{updateStandApproval()}}
    private var voiceGeneration:UInt64{listeningSession.revision}
    private var requestGeneration=UUID()
    private var started=false
    private var configurationGeneration=UUID()
    @Published private(set) var stateLoaded=false
    private var foreground=true
    private var notifications=Set<AnyCancellable>()

    init(configuration:AppConfiguration=AppConfiguration.load(),conversation:any ConversationResponding=ConversationService(),planner:any AgentPlanning=AgentPlanner()) {
        self.planner=planner
        self.conversation=conversation
        self.configuration=configuration
        wallet=WalletService(configuration:configuration)
        network=NetworkService(configuration:configuration)
        rpc=EthereumRPC(url:configuration.rpcURL,chainID:configuration.chainID)
        voice.onFinal={[weak self] text in self?.receiveSpeech(text)}
        voice.onPlaybackFinished={[weak self] in self?.resumeListening()}
        voice.onInputInterrupted={[weak self] in
            guard let self else{return}
            self.rest()
            if let message=self.voice.errorMessage{self.errorMessage=message}
        }
        voice.onInputIdle={[weak self] in self?.resumeListening()}
        sensors.onDetach={[weak self] in self?.rest()}
        sensors.onInterruption={[weak self] in
            guard let self else{return}
            self.rest()
            if let message=self.sensors.message ?? self.sensors.dockMessage{self.errorMessage=message}
        }
        NotificationCenter.default.publisher(for:AVAudioSession.interruptionNotification)
            .receive(on:DispatchQueue.main).sink{[weak self] _ in self?.rest()}.store(in:&notifications)
        NotificationCenter.default.publisher(for:AVAudioSession.mediaServicesWereResetNotification)
            .receive(on:DispatchQueue.main).sink{[weak self] _ in self?.rest()}.store(in:&notifications)
    }
    func start() async {
        guard !started else{return};started=true
        let startupGeneration=configurationGeneration
        let unavailable=await conversation.availability()
        guard configurationGeneration==startupGeneration else{return}
        modelUnavailable=unavailable
        var proofError:String?
        do{try await proofs.prepare()}catch{proofError=error.localizedDescription}
        guard configurationGeneration==startupGeneration else{return}
        proofUnavailable=proofError
        do {
            mandate=try LocalSecrets.read(StoredMandate.self,key:configuration.stateKey("active-mandate"))
            agentDelegation=UserDefaults.standard.bool(forKey:configuration.stateKey("agent-delegation-disabled")) ? nil : try LocalSecrets.read(AgentDelegation.self,key:configuration.stateKey("agent-delegation"))
            if let mandate{_=try mandate.policy.material()}
            identity=try LocalSecrets.read(MateIdentity.self,key:configuration.stateKey("mate-identity"))
            receipts=try LocalSecrets.read([ExecutionReceipt].self,key:configuration.stateKey("receipts")) ?? []
            pendingExecution=try LocalSecrets.read(PendingExecution.self,key:configuration.stateKey("pending-execution"))
            localNotes=try LocalSecrets.read(String.self,key:"local-notes") ?? ""
            stateLoaded=true
            if configuration.walletConfigured{try await wallet.restore()}
        }catch{
            guard configurationGeneration==startupGeneration else{return}
            if !stateLoaded{started=false}
            errorMessage=error.localizedDescription
        }
    }
    func applyConfiguration(_ proposed:AppConfiguration,pairingCode:String="") async {
        var value=proposed
        let sameEnvironment=value.sameEnvironment(as:configuration)
        guard !financialBusy else{return}
        guard stateLoaded else{errorMessage="Unlock your phone and reopen Mate to restore pending operations first.";return}
        guard sameEnvironment || pendingExecution == nil else{errorMessage="Recover the pending execution before changing connections.";return}
        do {
            if !sameEnvironment, try LocalSecrets.read(PendingGrant.self,key:configuration.stateKey("pending-grant")) != nil {
                errorMessage="Recover the pending mandate before changing connections.";return
            }
        }catch{errorMessage=error.localizedDescription;return}
        guard value.deploymentConfigured else{errorMessage="Enter a supported testnet, matching USDC token and vault.";return}
        guard !pairingCode.isEmpty || (sameEnvironment && value.pairingValid) else{errorMessage="Create a one-time pairing code on your Mac, then enter it here.";return}
        financialBusy=true;stopVoice();sensors.stopCapture();cancelConversation()
        let ticket=requestGeneration
        defer{financialBusy=false}
        do {
            var candidate=NetworkService(configuration:value)
            try await candidate.validateDeployment()
            let candidateRPC=EthereumRPC(url:value.rpcURL,chainID:value.chainID)
            try await candidateRPC.ensureNetwork()
            guard foreground,requestGeneration==ticket else{throw ProductError.cancelled}
            if !pairingCode.isEmpty {
                value=try await candidate.pair(code:pairingCode.trimmingCharacters(in:.whitespacesAndNewlines))
                candidate=NetworkService(configuration:value)
            }
            try await candidate.validatePairing()
            guard foreground,requestGeneration==ticket else{throw ProductError.cancelled}
            try LocalSecrets.write(value,key:"connection-settings")
            if sameEnvironment {
                configuration=value;network=candidate;rpc=candidateRPC
                errorMessage=nil
                sheet = sheet == .setup ? .setup : .settings
                return
            }
            let returnToSetup=sheet == .setup
            configurationGeneration=UUID();stateLoaded=false;setupConnected=false;accountCheckedAt=nil
            configuration=value;network=candidate;rpc=candidateRPC;wallet=WalletService(configuration:value)
            mandate=nil;agentDelegation=nil;account=nil;spent=0;receipts=[];identity=nil;providers=[];discoveryEvidence=nil
            // draft contains no payment authority; preserve the user's task while
            // connecting, but cancelConversation above invalidates the old offer.
            started=false;sheet = returnToSetup ? .setup : .settings
            await start()
        }catch{errorMessage=error.localizedDescription}
    }
    private func cancelConversation() {
        agentOffer=nil;revokeOffer=nil
        conversationGeneration &+= 1
        conversationTask?.cancel();conversationTask=nil;thinking=false
    }
    func clearRuleDraft() { ruleDraft=nil }
    func setForeground(_ active:Bool) {
        foreground=active;sensors.setForeground(active)
        if !active{rest()}
        else if !stateLoaded {Task{await start()}}
    }
    func stopVoice(){listeningSession.stop();awaitingGreeting=false;preparingCompanion=false;voice.stop()}
    func armVoiceWake() async {
        guard foreground,!financialBusy,!thinking else{return}
        rest();listeningSession.begin();awaitingGreeting=true;recognitionLocale="ja-JP"
        let ticket=voiceGeneration
        await voice.start(locale:recognitionLocale)
        guard ticket==voiceGeneration else{return}
        if !voice.listening {rest();if let message=voice.errorMessage{errorMessage=message}}
    }
    private func receiveSpeech(_ text:String) {
        if VoiceWakePhrase.isRestCommand(text){rest();return}
        guard awaitingGreeting else{send(text);return}
        guard VoiceWakePhrase.matches(text) else{resumeListening();return}
        stopVoice()
        let ticket=voiceGeneration
        Task{[weak self] in
            guard let self,self.foreground,self.voiceGeneration==ticket else{return}
            await self.startCompanion(voiceLocale:"ja-JP")
            if self.voiceSessionActive,self.voice.listening{self.send(text)}
        }
    }
    private func resumeListening() {
        let generation=voiceGeneration
        Task{[weak self] in
            guard let self,self.canResumeListening(generation) else{return}
            await Task.yield()
            guard self.canResumeListening(generation) else{return}
            await self.voice.start(locale:self.recognitionLocale)
            if self.voiceGeneration==generation,!self.voice.listening {
                self.rest()
                if let message=self.voice.errorMessage{self.errorMessage=message}
            }
        }
    }
    private func canResumeListening(_ ticket:UInt64) -> Bool {
        listeningSession.permitsResume(ticket:ticket,foreground:foreground,resting:sleeping && !awaitingGreeting,
            busy:thinking || financialBusy || preparingCompanion,
            screenAllowsListening:sheet == nil || sheet == .conversation || sheet == .controls)
    }
    func rest(){requestGeneration=UUID();sleeping=true;stopVoice();sensors.stopCapture();cancelConversation();outcomeTask?.cancel();lastOutcome=nil}
    /// Capture before asynchronous work. Recording a confirmed transaction may
    /// outlive the interaction, but its feedback must not wake a stopped Mate.
    func makeOutcomeFeedback() -> (ExecutionOutcome)->Void {
        let ticket=requestGeneration
        return { [weak self] outcome in
            guard let self,self.foreground,!self.sleeping,self.requestGeneration==ticket else{return}
            self.flashOutcome(outcome)
        }
    }
    /// Shown only for a fixed, short window, then cleared. Never re-armed by a
    /// later, unrelated interaction reading a stale value.
    private func flashOutcome(_ outcome:ExecutionOutcome) {
        outcomeTask?.cancel();lastOutcome=outcome
        sensors.requestReaction(outcome)
        outcomeTask=Task{[weak self] in
            do{try await Task.sleep(for:.milliseconds(1_600))}catch{return}
            guard let self,!Task.isCancelled,self.lastOutcome==outcome else{return}
            self.lastOutcome=nil
        }
    }
    func wake(){sleeping=false}
    func saveNotes() {
        guard localNotes.utf8.count<=2_000 else{errorMessage="Keep notes within 2,000 bytes.";return}
        do{try LocalSecrets.write(localNotes,key:"local-notes")}catch{errorMessage=error.localizedDescription}
    }
    func clearConversation(){requestGeneration=UUID();cancelConversation();stopVoice();messages=[];draft=nil}
    func send(_ text:String) {
        let input=text.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !thinking,!financialBusy,!input.isEmpty,foreground else{return}
        guard input.count<=2_200 else{errorMessage="Keep each message within 2,200 characters.";return}
        errorMessage=nil
        sleeping=false;voice.stop();thinking=true
        conversationGeneration &+= 1
        let generation=conversationGeneration
        let history=messages.suffix(8).map{($0.isUser ? "User: ":"Mate: ")+$0.text}.joined(separator:"\n")
        messages.append(ConversationMessage(isUser:true,text:input));messages=Array(messages.suffix(40))
        let notes=localNotes
        let replyLanguage=ConversationLanguage.detect(input,fallback:L10n.speechLanguage)
        recognitionLocale=replyLanguage.speechLocale
        conversationTask=Task{[weak self] in
            guard let self else{return}
            defer{
                if self.conversationGeneration==generation {
                    self.thinking=false
                    if !self.voice.speaking{self.resumeListening()}
                }
            }
            do {
                let control=input.lowercased().filter{!$0.isWhitespace && !$0.isPunctuation}
                if ["注文を確認して","注文どうなった","注文の状況を教えて","checkmyorder","checktheorder","orderstatus"].contains(control) {
                    self.agentOffer=nil;self.revokeOffer=nil
                    guard self.stateLoaded else {
                        self.agentSay(replyLanguage == .japanese ? "保存済みの注文を復元しています。ロックを解除してMateを開いてください。" : "I'm still restoring saved orders. Unlock the phone and reopen Mate before checking the result.",language:replyLanguage)
                        return
                    }
                    if self.pendingExecution == nil && ShopCheckout.hasSavedOrder() {
                        self.openShop(language: replyLanguage)
                        self.agentSay(replyLanguage == .japanese ? "保存したビールの注文を確認します。新しく支払いはしません。" : "I'll check your saved beer order. This won't create a new payment.", language: replyLanguage)
                    } else if self.pendingExecution != nil {
                        self.executionStatus=replyLanguage == .japanese ? "同じ注文の結果を確認しています" : "Checking the existing order"
                        await self.recoverExecution()
                        self.executionStatus=nil
                        guard self.foreground,self.conversationGeneration==generation else{return}
                        self.reportAgentResult(language:replyLanguage)
                    } else {
                        self.agentSay(replyLanguage == .japanese ? "確認待ちの注文はありません。過去の結果は履歴に残しています。" : "There are no pending orders. Earlier results are saved in Activity.",language:replyLanguage)
                    }
                    return
                }
                if let offered=self.agentOffer {
                    self.agentOffer=nil
                    if offered.accepts(input,draftID:self.draft?.id,generation:self.requestGeneration) {
                        self.agentSay(replyLanguage == .japanese ? "このiPhoneで証明を作って注文します。" : "I'll create the proof on this iPhone and place the order.",language:replyLanguage)
                        await self.execute(payload:offered.request.text,provider:offered.provider,fromAgent:true)
                        guard self.foreground,self.conversationGeneration==generation else{return}
                        self.reportAgentResult(language:replyLanguage)
                        return
                    }
                }
                if let offered=self.revokeOffer {
                    self.revokeOffer=nil
                    if offered.accepts(input,generation:self.requestGeneration),self.mandate?.id==offered.mandateID {
                        await self.fund(.revoke(offered.mandateID))
                        guard self.foreground,self.conversationGeneration==generation else{return}
                        if let failure=self.errorMessage {
                            self.errorMessage=nil
                            self.agentSay((replyLanguage == .japanese ? "委任を取り消せませんでした。" : "I couldn't revoke the mandate. ")+L10n.text(failure),language:replyLanguage)
                        } else if self.mandate == nil {
                            self.agentSay(replyLanguage == .japanese ? "委任を取り消しました。" : "The mandate has been revoked.",language:replyLanguage)
                        }
                        return
                    }
                }
                if !self.stateLoaded && (ConversationRouter.isUsageStatusRequest(input) || ConversationRouter.isRevokeRequest(input)) {
                    self.agentSay(replyLanguage == .japanese ? "保存済みの委任を復元しています。少し待ってからもう一度確認してください。" : "I'm restoring saved mandates. Please check again shortly.",language:replyLanguage)
                    return
                }
                if ConversationRouter.isUsageStatusRequest(input) {
                    self.agentOffer=nil;self.revokeOffer=nil
                    guard let stored=self.mandate else {
                        self.agentSay(replyLanguage == .japanese ? "有効な予算の設定はまだありません。「あなたのルール」から設定できます。" : "There is no active spending mandate yet. Set one up from Your rules.",language:replyLanguage)
                        return
                    }
                    self.executionStatus=replyLanguage == .japanese ? "利用状況を確認しています" : "Checking usage"
                    self.errorMessage=nil
                    await self.refreshAccount()
                    self.executionStatus=nil
                    guard self.foreground,self.conversationGeneration==generation else{return}
                    if let failure=self.errorMessage {
                        self.errorMessage=nil
                        self.agentSay((replyLanguage == .japanese ? "利用状況を確認できませんでした。" : "I couldn't confirm the current usage. ")+L10n.text(failure),language:replyLanguage)
                    } else if self.mandate?.id == stored.id, let checkedAt=self.accountCheckedAt {
                        let remaining=TokenAmount(units:stored.policy.budget>self.spent ? stored.policy.budget-self.spent:0).display
                        let timestamp=checkedAt.formatted(date:.omitted,time:.standard)
                        self.agentSay(replyLanguage == .japanese
                            ? "確認時刻\(timestamp)。これまでに\(TokenAmount(units:self.spent).display) USDC使いました。残りは\(remaining) USDCです。"
                            : "As of \(timestamp), you've spent \(TokenAmount(units:self.spent).display) USDC so far, with \(remaining) USDC remaining.",language:replyLanguage)
                    } else {
                        self.agentSay(replyLanguage == .japanese ? "現在の委任は失効または期限切れです。" : "The mandate is revoked or expired.",language:replyLanguage)
                    }
                    return
                }
                if ConversationRouter.isRevokeRequest(input) {
                    self.agentOffer=nil
                    guard let stored=self.mandate else {
                        self.agentSay(replyLanguage == .japanese ? "現在、取り消す委任はありません。" : "There is no active mandate to revoke.",language:replyLanguage)
                        return
                    }
                    self.revokeOffer=PendingRevoke(mandateID:stored.id,generation:self.requestGeneration,createdAt:Date())
                    self.errorMessage=nil
                    let limit=TokenAmount(units:stored.policy.budget).display
                    self.agentSay(replyLanguage == .japanese
                        ? "\(self.configuration.networkName)の委任\(stored.id)（上限\(limit) USDC）を取り消します。よろしければ「はい」と言ってください。"
                        : "This will revoke mandate \(stored.id) on \(self.configuration.networkName) (limit \(limit) USDC). Say yes to confirm.",language:replyLanguage)
                    return
                }
                if let proposal=ConversationRouter.ruleProposal(from:input) {
                    self.agentOffer=nil;self.revokeOffer=nil
                    guard proposal.translation || proposal.summary else {
                        self.agentSay(replyLanguage == .japanese ? "翻訳と要約のどちらに使ってよいか教えてください。" : "Let me know whether this can be used for translation, summary or both.",language:replyLanguage)
                        return
                    }
                    guard self.mandate == nil else {
                        self.agentSay(replyLanguage == .japanese ? "ルールを変更するには、現在の委任を先に「あなたのルール」から取り消してください。" : "Changing the rules requires revoking the current mandate first, from Your rules.",language:replyLanguage)
                        return
                    }
                    self.ruleDraft=proposal
                    self.sheet = .rules
                    if let unsupported=proposal.unsupportedService {
                        self.agentSay(replyLanguage == .japanese
                            ? "「\(unsupported)」はまだ対応していません。翻訳・要約の範囲で提案を「あなたのルール」に用意しました。金額と期限を確認して承認してください。"
                            : "\"\(unsupported)\" isn't supported yet. I've prepared a proposal limited to translation and summary on Your rules. Review the amount and expiry, then approve it there.",language:replyLanguage)
                    } else {
                        self.agentSay(replyLanguage == .japanese ? "提案を「あなたのルール」に用意しました。金額と期限を確認して承認してください。" : "I've prepared this proposal on Your rules. Review the amount and expiry, then approve it there.",language:replyLanguage)
                    }
                    return
                }
                if ShopPlanner.relevant(input) {
                    let plan = try await self.shopPlanner.plan(input)
                    try Task.checkCancellation()
                    guard self.foreground, self.conversationGeneration == generation else { return }
                    switch plan.operation {
                    case .buyBeer:
                        guard plan.quantity == 1 else {
                            self.agentSay(replyLanguage == .japanese ? "今の店舗は1本ずつの注文に対応しています。1本を注文する場合は、そう話しかけてください。" : "The store currently accepts one bottle per order. Ask me for one bottle if that's what you'd like.", language: replyLanguage)
                            return
                        }
                        self.openShop(language: replyLanguage)
                        self.agentSay(replyLanguage == .japanese
                            ? "Mate Lagerを1本、0.10テストUSDCで注文できます。内容を確認したら、カードをタッチしてください。生年月日はiPhoneに残したまま証明します。"
                            : "I can order one Mate Lager for 0.10 test USDC. Review the order, then tap your card. Your birth date stays on this iPhone.", language: replyLanguage)
                        return
                    case .unsupportedPurchase:
                        self.agentSay(replyLanguage == .japanese ? "今つながっている店舗で買えるのはMate Lagerです。Amazonやほかの商品はまだ注文できません。" : "The connected store sells Mate Lager. Amazon and other products aren't connected yet.", language: replyLanguage)
                        return
                    case .chat: break
                    }
                }
                if let request=try await self.planner.request(from:input) {
                    try Task.checkCancellation()
                    guard self.foreground,self.conversationGeneration==generation else{return}
                    await self.prepareAgent(request,language:replyLanguage,generation:generation)
                    return
                }
                let response=try await self.conversation.reply(to:input,history:history,
                    observations:self.sensors.currentObservation,notes:notes,replyLanguage:replyLanguage.name)
                try Task.checkCancellation()
                guard self.foreground,self.conversationGeneration==generation else{return}
                self.messages.append(ConversationMessage(isUser:false,text:response.text))
                if let service=response.service,!response.disclosure.isEmpty {
                    self.draft=DisclosureDraft(service:service,text:response.disclosure)
                }
                if self.readAloud{self.voice.speak(response.text,locale:replyLanguage.speechLocale)}
            }catch is CancellationError{}catch{
                if self.conversationGeneration==generation{self.rest();self.errorMessage=error.localizedDescription}
            }
        }
    }
    private func agentSay(_ text:String,language:AppLanguage) {
        messages.append(ConversationMessage(isUser:false,text:text));messages=Array(messages.suffix(40))
        if readAloud{voice.speak(text,locale:language.speechLocale)}
    }
    func finishShopConversation() {
        let language = shopReplyLanguage
        agentSay(language == .japanese ? "Mate Lagerのテスト購入が完了しました。カードの情報はこのiPhoneに残したままです。" : "Your Mate Lager test purchase is complete. Your card details stayed on this iPhone.", language: language)
    }
    func openShop(language: AppLanguage = .english) { shopReplyLanguage = language; sheet = .shop }
    private func reportAgentResult(language:AppLanguage) {
        if let message=errorMessage {
            errorMessage=nil
            agentSay((language == .japanese ? "完了を確認できません。" : "I couldn't confirm completion. ")+L10n.text(message),language:language)
        } else if let receipt=receipts.first {
            agentSay(receipt.result,language:ConversationLanguage.detect(receipt.result,fallback:language))
        }
    }
    func permitAgent(provider:ServiceProvider) async {
        guard !financialBusy,foreground,!sleeping,let stored=mandate,providers.contains(provider),
              let amount=UInt64(provider.price),amount>0,let service=MateService(rawValue:provider.service) else{return}
        let ticket=requestGeneration
        financialBusy=true
        defer{financialBusy=false}
        do {
            try stored.policy.check(spent:spent,amount:amount,service:service)
            let context=LAContext()
            let reason="Allow Mate to send future \(service.title) requests to this shop for up to \(TokenAmount(units:amount).display) test USDC each, within your existing mandate"
            guard try await context.evaluatePolicy(.deviceOwnerAuthentication,localizedReason:reason),
                  foreground,!sleeping,requestGeneration==ticket,mandate?.id==stored.id else{throw ProductError.cancelled}
            let consent=AgentDelegation(chainID:configuration.chainID,vault:configuration.vault,mandateID:stored.id,
                providerID:provider.id,recipient:provider.recipient,service:provider.service,maximumAmount:amount,
                validUntil:stored.grant.validUntil)
            try LocalSecrets.write(consent,key:configuration.stateKey("agent-delegation"))
            UserDefaults.standard.set(false,forKey:configuration.stateKey("agent-delegation-disabled"))
            agentDelegation=consent
        }catch{errorMessage=error.localizedDescription}
    }
    func stopAgentDelegation() {
        requestGeneration=UUID();agentOffer=nil;agentDelegation=nil
        UserDefaults.standard.set(true,forKey:configuration.stateKey("agent-delegation-disabled"))
        do {try LocalSecrets.delete(configuration.stateKey("agent-delegation"))}
        catch{errorMessage=error.localizedDescription}
    }
    private func delegationAllows(_ provider:ServiceProvider,mandateID:String,now:UInt64)->Bool {
        guard let amount=UInt64(provider.price) else{return false}
        return agentDelegation?.permits(chainID:configuration.chainID,vault:configuration.vault,mandateID:mandateID,
            providerID:provider.id,recipient:provider.recipient,service:provider.service,amount:amount,now:now) == true
    }
    private func prepareAgent(_ request:AgentRequest,language:AppLanguage,generation:UInt64) async {
        let ja=language == .japanese
        guard pendingExecution == nil else {
            agentSay(ja ? "前の注文が確認待ちです。二重注文を避けるため、履歴から先に結果を確認してください。" : "An earlier order is still pending. Check its result in Activity before starting another order.",language:language)
            return
        }
        draft=DisclosureDraft(service:request.service,text:request.text)
        providers=[];discoveryEvidence=nil
        guard !requestNeedsSetup else {
            agentSay(ja ? "依頼内容をこのiPhoneに残しました。まだ送信も支払いもしていません。会話の「依頼を続ける」から接続と予算を設定できます。準備ができたら、この文章と料金を確認して進めましょう。" : "I've kept your request on this iPhone. Nothing has been sent or paid. Open Continue request in the conversation to connect and set your budget, then review this text and the price.",language:language)
            return
        }
        let preflightFeedback=makeOutcomeFeedback()
        executionStatus=ja ? "店舗の料金を確認しています" : "Checking shop prices"
        defer{executionStatus=nil}
        do {
            let response=try await network.providers(service:request.service)
            try Task.checkCancellation()
            guard foreground,!sleeping,conversationGeneration==generation,let draft else{return}
            guard response.providers.allSatisfy({$0.service==request.service.rawValue && UInt64($0.price) != nil}) else{throw ProductError.invalidResponse}
            providers=response.providers
            let preferred=providers.first{delegationAllows($0,mandateID:mandate?.id ?? "",now:UInt64(Date().timeIntervalSince1970))}
            guard let provider=preferred ?? providers.sorted(by:{UInt64($0.price)! < UInt64($1.price)!}).first,
                  let amount=UInt64(provider.price),let stored=mandate else {
                throw ProductError.unavailable("No active provider meets these requirements.")
            }
            let state=try await network.mandate(id:stored.id)
            try Task.checkCancellation()
            guard foreground,!sleeping,conversationGeneration==generation,self.draft?.id==draft.id else{return}
            guard let currentSpent=UInt64(state.spent),!state.revoked,state.validUntil>UInt64(Date().timeIntervalSince1970)+60 else{throw ProductError.invalidResponse}
            try stored.policy.check(spent:currentSpent,amount:amount,service:request.service)
            if request.directInstruction && delegationAllows(provider,mandateID:stored.id,now:UInt64(Date().timeIntervalSince1970)) {
                agentSay(ja ? "任せてもらった範囲内です。\(provider.name)に\(TokenAmount(units:amount).display)テストUSDCで注文します。予算のルールはこのiPhoneに残して、証明を送ります。" : "This is within your approved terms. I'll order from \(provider.name) for \(TokenAmount(units:amount).display) test USDC, sending a proof while keeping your private rules on this iPhone.",language:language)
                await execute(payload:request.text,provider:provider,fromAgent:true,requiresDelegation:true)
                guard foreground,conversationGeneration==generation else{return}
                reportAgentResult(language:language)
                return
            }
            agentOffer=AgentOffer(request:request,provider:provider,draftID:draft.id,generation:requestGeneration,createdAt:Date())
            let price=String(format:"%.6f",Double(amount)/1_000_000)
            let prompt=ja ? "「\(request.text)」を\(provider.name)に送って処理します。料金は\(price)テストUSDCです。この内容と金額で進めてよければ、はいと言ってください。" : "I'll send ‘\(request.text)’ to \(provider.name). The price is \(price) test USDC. Say yes to approve this exact text and price."
            agentSay(prompt,language:language)
        } catch {
            guard foreground,conversationGeneration==generation else{return}
            if let rejection=error as? MandateError,
               rejection == .overBudget || rejection == .serviceNotAllowed,
               pendingExecution == nil {preflightFeedback(.rejected)}
            agentSay((ja ? "注文前の確認で止まりました。" : "I stopped before placing the order. ")+L10n.text(error.localizedDescription),language:language)
        }
    }
    func startCompanion(voiceLocale:String? = nil) async {
        if awaitingGreeting{stopVoice()}
        guard foreground,!financialBusy,!thinking,!preparingCompanion,!voiceSessionActive else{return}
        stopVoice();listeningSession.begin()
        recognitionLocale=voiceLocale
        let ticket=voiceGeneration
        preparingCompanion=true
        // Looking at the user must not depend on speech/model availability.
        // This method is entered only after the user's explicit start action.
        sleeping=false
        defer{if voiceGeneration==ticket{preparingCompanion=false}}
        let cameraStarted=await sensors.startCaptureAndWait()
        guard voiceGeneration==ticket,foreground else{return}
        guard cameraStarted else{rest();return}
        let unavailable=await conversation.availability()
        guard voiceGeneration==ticket,foreground else{return}
        modelUnavailable=unavailable
        if let unavailable {errorMessage=unavailable;return}
        continuousConversation=true
        await voice.start(locale:recognitionLocale)
        guard voiceGeneration==ticket,foreground else{return}
        guard voice.listening else{stopVoice();if let error=voice.errorMessage{errorMessage=error};return}
        sleeping=false
    }
    /// Stops a reply and invalidates its late completion without changing a
    /// submitted financial operation or starting any sensor.
    @discardableResult func interruptReply() -> Bool {
        guard foreground,!financialBusy else{return false}
        requestGeneration=UUID();cancelConversation();stopVoice()
        return true
    }
    func speakNow() async {
        guard !voice.requestingPermission,interruptReply() else{return}
        sleeping=false;errorMessage=nil;continuousConversation=true
        listeningSession.begin()
        let ticket=voiceGeneration
        await voice.start(locale:recognitionLocale)
        guard ticket==voiceGeneration,foreground else{return}
        if !voice.listening {
            stopVoice()
            if let message=voice.errorMessage{errorMessage=message}
        }
    }
    func toggleVoice() async {
        if voiceSessionActive{stopVoice();cancelConversation()}
        else if voice.requestingPermission{stopVoice()}
        else if voice.listening{let text=voice.finish();send(text)}
        else{
            guard !thinking,!financialBusy,foreground else{return};sleeping=false
            listeningSession.stop()
            if continuousConversation{listeningSession.begin()}
            await voice.start()
            if !voice.listening{listeningSession.stop()}
        }
    }
    func makeDraft(service:MateService,text:String="") {
        guard !financialBusy else{return}
        stopVoice();providers=[];discoveryEvidence=nil
        draft=DisclosureDraft(service:service,text:text);sheet = .disclosure
    }
    func findProviders(service:MateService) async {
        guard !discovering, let draftID=draft?.id, draft?.service==service else{return};discovering=true;providers=[];discoveryEvidence=nil
        defer{discovering=false}
        do {
            let response=try await network.providers(service:service)
            guard draft?.id==draftID, foreground, !sleeping else{return}
            guard response.providers.allSatisfy({$0.service==service.rawValue && UInt64($0.price) != nil}) else{throw ProductError.invalidResponse}
            providers=response.providers;discoveryEvidence=L10n.format("The Graph · block %@",response.indexedBlock)
            if providers.isEmpty{throw ProductError.unavailable("No active provider meets these requirements. No preset alternative will be substituted.")}
        }catch{if draft?.id==draftID,foreground,!sleeping{errorMessage=error.localizedDescription}}
    }
    @Published private(set) var setupConnected=false
    @Published private(set) var setupChecking=false
    @Published private(set) var setupMessage:String?
    @Published private(set) var setupHasPendingGrant=false
    var setupProgress:SetupProgress {
        SetupProgress(restored:stateLoaded,pending:pendingExecution != nil || setupHasPendingGrant,
            connected:setupConnected && configuration.paymentsConfigured && configuration.walletConfigured,
            authenticated:wallet.isAuthenticated,walletsReady:wallet.ownerAddress != nil && wallet.agentAddress != nil,
            accountChecked:accountCheckedAt != nil,balance:UInt64(account?.balance ?? "") ?? 0,
            mandateActive:mandate.map{$0.grant.validUntil>UInt64(Date().timeIntervalSince1970) && $0.policy.budget>spent} ?? false)
    }
    var setupCheckpointKey:String {
        let identity="\(configuration.chainID):\(configuration.vault.lowercased()):\(configuration.apiURL):\(configuration.privyAppID)"
        return "setup:"+LocalSecrets.hash(Data(identity.utf8))
    }
    func refreshSetup() async {
        guard stateLoaded,!setupChecking,!financialBusy else{return}
        setupChecking=true;setupMessage=nil;setupConnected=false
        let generation=configurationGeneration
        defer{
            setupChecking=false
            if configurationGeneration==generation{UserDefaults.standard.set(setupProgress.stage.rawValue,forKey:setupCheckpointKey)}
        }
        do {
            setupHasPendingGrant=try LocalSecrets.read(PendingGrant.self,key:configuration.stateKey("pending-grant")) != nil
            if pendingExecution != nil || setupHasPendingGrant {return}
            guard configuration.paymentsConfigured && configuration.walletConfigured else{return}
            try await network.validateDeployment()
            try await rpc.ensureNetwork()
            guard configurationGeneration==generation,foreground else{return}
            setupConnected=true
            try await wallet.restore()
            guard configurationGeneration==generation,foreground else{return}
            if wallet.ownerAddress != nil {
                errorMessage=nil
                await refreshAccount()
                if let errorMessage{setupMessage=errorMessage;self.errorMessage=nil}
            }
        }catch{if configurationGeneration==generation{setupMessage=error.localizedDescription}}
    }
    @Published private(set) var accountCheckedAt:Date?
    func refreshAccount() async {
        let scope=configurationGeneration
        let currentNetwork=network
        let mandateID=mandate?.id
        accountCheckedAt=nil
        guard let owner=wallet.ownerAddress else{errorMessage="Set up your wallet and settlement connection first.";return}
        do {
            let fetchedAccount=try await currentNetwork.account(owner:owner)
            guard configurationGeneration==scope,wallet.ownerAddress==owner,mandate?.id==mandateID else{return}
            if let mandate {
                let state=try await currentNetwork.mandate(id:mandate.id)
                guard configurationGeneration==scope,wallet.ownerAddress==owner,self.mandate?.id==mandateID else{return}
                guard state.owner.lowercased()==mandate.grant.owner.lowercased(),
                      state.agent.lowercased()==mandate.grant.agent.lowercased(),
                      state.policyHash.lowercased()==mandate.grant.policyHash.lowercased(),let value=UInt64(state.spent) else{throw ProductError.invalidResponse}
                spent=value
                if state.revoked || state.validUntil<=UInt64(Date().timeIntervalSince1970) {
                    try LocalSecrets.delete(configuration.stateKey("active-mandate"));self.mandate=nil
                }
            }
            account=fetchedAccount;accountCheckedAt=Date()
        }catch{if configurationGeneration==scope{errorMessage=error.localizedDescription}}
    }
    func authorize(budget:String,translation:Bool,summary:Bool,hours:Int,validUntil:Date?=nil) async {
        guard stateLoaded else{errorMessage="Unlock your phone and reopen Mate to restore pending operations first.";return}
        let approvalGeneration=requestGeneration
        func validateApproval() throws { guard foreground,!sleeping,requestGeneration==approvalGeneration else{throw ProductError.cancelled} }
        guard !financialBusy else{return}
        guard mandate == nil else{errorMessage="Revoke the current mandate before changing its terms.";return}
        guard let owner=wallet.ownerAddress,let agent=wallet.agentAddress,configuration.paymentsConfigured else{
            errorMessage="Set up your wallet and settlement connection first.";return
        }
        financialBusy=true;stopVoice();sensors.stopCapture();defer{financialBusy=false;executionStatus=nil}
        do {
            guard try LocalSecrets.read(PendingGrant.self,key:configuration.stateKey("pending-grant")) == nil else{
                throw ProductError.unavailable("A mandate is awaiting confirmation. Recover it and check its status first.")
            }
            guard (1...24).contains(hours) else{throw MandateError.invalidPolicy}
            let now=Date()
            let expiry=validUntil ?? now.addingTimeInterval(Double(hours*3600))
            guard expiry > now,expiry.timeIntervalSince(now)<=24*3600 else{throw MandateError.invalidPolicy}
            let policy=try PrivatePolicy(budget:TokenAmount(decimal:budget).units,
                services:(translation ? 1:0)|(summary ? 2:0),salt:LocalSecrets.random32())
            let state=try await network.account(owner:owner)
            let grant=try MandateGrant(owner:owner,agent:agent,policyHash:LocalSecrets.hash(policy.material()),
                validUntil:UInt64(expiry.timeIntervalSince1970),nonce:state.nonce)
            reportExecution(.approval,"Verifying owner approval")
            let signature=try await wallet.signGrant(grant,validateApproval:validateApproval)
            let pending=PendingGrant(grant:grant,policy:policy,signature:signature)
            try LocalSecrets.write(pending,key:configuration.stateKey("pending-grant"))
            reportExecution(.sending,L10n.format("Registering the mandate on %@",L10n.text(configuration.networkName)))
            try await finishGrant(pending)
        }catch{errorMessage=error.localizedDescription}
    }
    private func finishGrant(_ pending:PendingGrant) async throws {
        reportExecution(.sending,L10n.format("Registering the mandate on %@",L10n.text(configuration.networkName)))
        let receipt=try await network.register(grant:pending.grant,signature:pending.signature)
        reportExecution(.confirming,L10n.format("Waiting for %@ confirmation",L10n.text(configuration.networkName)))
        _=try await rpc.confirm(hash:receipt.transactionHash)
        let state=try await network.mandate(id:receipt.mandateId)
        guard state.owner.lowercased()==pending.grant.owner.lowercased(),state.agent.lowercased()==pending.grant.agent.lowercased(),
              state.policyHash.lowercased()==pending.grant.policyHash.lowercased(),state.validUntil==pending.grant.validUntil,
              !state.revoked,let value=UInt64(state.spent) else{throw ProductError.invalidResponse}
        let stored=StoredMandate(id:receipt.mandateId,grant:pending.grant,policy:pending.policy)
        try LocalSecrets.write(stored,key:configuration.stateKey("active-mandate"));try LocalSecrets.delete(configuration.stateKey("pending-grant"))
        mandate=stored;spent=value
    }
    func recoverGrant() async {
        guard !financialBusy else{return};financialBusy=true;defer{financialBusy=false;executionStatus=nil}
        do {
            guard let pending=try LocalSecrets.read(PendingGrant.self,key:configuration.stateKey("pending-grant")) else{
                throw ProductError.unavailable("There is no pending mandate.")
            }
            try await finishGrant(pending)
        }catch{errorMessage=error.localizedDescription}
    }
    func fund(_ operation:WalletService.FundingOperation) async {
        guard stateLoaded else{errorMessage="Unlock your phone and reopen Mate to restore pending operations first.";return}
        let approvalGeneration=requestGeneration
        func validateApproval() throws { guard foreground,!sleeping,requestGeneration==approvalGeneration else{throw ProductError.cancelled} }
        guard !financialBusy else{return}
        financialBusy=true;stopVoice();sensors.stopCapture();defer{financialBusy=false;executionStatus=nil}
        do {
            reportExecution(.approval,"Verifying signature")
            let hash=try await wallet.send(operation,validateApproval:validateApproval)
            reportExecution(.confirming,L10n.format("Waiting for %@ confirmation",L10n.text(configuration.networkName)))
            _=try await rpc.confirm(hash:hash)
            if case .revoke=operation{try LocalSecrets.delete(configuration.stateKey("active-mandate"));mandate=nil}
            await refreshAccount()
        }catch{errorMessage=error.localizedDescription}
    }
    func execute(payload:String,provider:ServiceProvider,fromAgent:Bool=false,requiresDelegation:Bool=false) async {
        guard stateLoaded else{errorMessage="Unlock your phone and reopen Mate to restore pending operations first.";return}
        guard !financialBusy else{return}
        guard foreground,!sleeping else{errorMessage="Wake Mate before making a request.";return}
        if let reason=proofUnavailable{errorMessage=reason;return}
        guard pendingExecution == nil else{errorMessage="A transaction is awaiting confirmation. Check Activity before retrying to avoid duplicate execution.";return}
        guard let approvedDraft=draft, let stored=mandate,let service=MateService(rawValue:provider.service),let amount=UInt64(provider.price),
              approvedDraft.service==service,
              providers.contains(provider),!payload.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
              payload.utf8.count<=8_000 else{errorMessage="Check the mandate, provider and text to share.";return}
        let ticket=requestGeneration
        let feedback=makeOutcomeFeedback()
        func checkApproval() throws {
            guard foreground, !sleeping, requestGeneration==ticket, draft?.id==approvedDraft.id else{throw ProductError.cancelled}
            if requiresDelegation && !delegationAllows(provider,mandateID:stored.id,now:UInt64(Date().timeIntervalSince1970)){throw ProductError.cancelled}
        }
        financialBusy=true
        if !fromAgent{stopVoice()}
        defer{financialBusy=false;executionStatus=nil}
        do {
            executionStatus="Checking approved terms"
            let state=try await network.mandate(id:stored.id)
            try checkApproval()
            let now=UInt64(Date().timeIntervalSince1970)
            guard !state.revoked,state.validUntil>now+15,state.policyHash.lowercased()==stored.grant.policyHash.lowercased(),
                  state.owner.lowercased()==wallet.ownerAddress?.lowercased(),state.agent.lowercased()==wallet.agentAddress?.lowercased(),
                  let spentBefore=UInt64(state.spent) else{throw ProductError.unavailable("The mandate was revoked or its owner could not be verified.")}
            try stored.policy.check(spent:spentBefore,amount:amount,service:service)
            let action=MandateAction(mandateId:stored.id,recipient:provider.recipient,amount:amount,service:service,
                nonce:CanonicalBytes.hexString(try LocalSecrets.random32()),expiresAt:min(now+300,state.validUntil),
                requestHash:LocalSecrets.hash(Data(payload.utf8)),spentBefore:spentBefore)
            reportExecution(.proving,"Generating a proof on this iPhone")
            let proof=try await proofs.prove(policy:stored.policy,action:action,chainID:configuration.chainID,vault:configuration.vault)
            try checkApproval()
            lastProofMilliseconds=proof.elapsedMilliseconds
            guard proof.policyHash.lowercased()==stored.grant.policyHash.lowercased() else{throw ProductError.invalidResponse}
            reportExecution(.thinking,"Signing with the restricted execution key")
            let signature=try await wallet.signAction(hash:proof.actionHash,validateApproval:checkApproval)
            try checkApproval()
            let submission=ExecutionSubmission(action:action,agentSignature:signature,proof:proof.bytes.base64EncodedString(),payload:payload,providerId:provider.id)
            let pending=PendingExecution(actionHash:proof.actionHash,proofHash:proof.proofHash,createdAt:Date(),submission:submission)
            try LocalSecrets.write(pending,key:configuration.stateKey("pending-execution"));pendingExecution=pending
            reportExecution(.sending,"Sending approved text and confirming execution")
            let receipt:ExecutionReceipt
            do {
                receipt=try await network.execute(action:action,signature:signature,proof:proof.bytes,payload:payload,providerID:provider.id)
            } catch {
                guard fromAgent else{throw error}
                try checkApproval()
                reportExecution(.confirming,"Checking the existing order without creating another payment")
                // One bounded recovery attempt, using the persisted action and nonce.
                // A lost response must never produce a second independently signed order.
                do {receipt=try await network.receipt(actionHash:pending.actionHash)}
                catch let failure as NetworkFailure where failure.code=="execution_not_found" {
                    try checkApproval()
                    receipt=try await network.submit(submission)
                }
            }
            try await accept(receipt,pending:pending)
            feedback(.confirmed)
            if requestGeneration==ticket {
                if !fromAgent{messages.append(ConversationMessage(isUser:false,text:receipt.result))}
                draft=nil
                if !fromAgent{sheet = .activity}
            }
        }catch{
            errorMessage=error.localizedDescription
            // A cancellation (rest, detach, superseded request) is not a condition
            // violation; only a real stop or rejection reason gets the shake.
            if case ProductError.cancelled=error {} else if !(error is CancellationError),pendingExecution == nil {feedback(.rejected)}
        }
    }
    private func accept(_ receipt:ExecutionReceipt,pending:PendingExecution) async throws {
        guard receipt.actionHash.lowercased()==pending.actionHash.lowercased(),receipt.proofHash.lowercased()==pending.proofHash.lowercased(),
              let value=UInt64(receipt.spentAfter) else{throw ProductError.invalidResponse}
        reportExecution(.confirming,"Verifying the execution receipt.")
        try await rpc.confirmExecution(receipt,pending:pending,vault:configuration.vault)
        spent=value;receipts.removeAll{$0.id==receipt.id};receipts.insert(receipt,at:0);receipts=Array(receipts.prefix(30))
        try LocalSecrets.write(receipts,key:configuration.stateKey("receipts"));try LocalSecrets.delete(configuration.stateKey("pending-execution"));pendingExecution=nil
    }
    func recoverExecution() async {
        guard !financialBusy,let pending=pendingExecution else{return}
        let feedback=makeOutcomeFeedback()
        financialBusy=true;defer{financialBusy=false;executionStatus=nil}
        reportExecution(.confirming,"Checking the existing order without creating another payment")
        do {
            let receipt:ExecutionReceipt
            do{receipt=try await network.receipt(actionHash:pending.actionHash)}
            catch let failure as NetworkFailure where failure.code=="execution_not_found" {
                guard let submission=pending.submission else{
                    throw ProductError.unavailable("Could not restore the request. Check whether it can be cancelled before payment.")
                }
                receipt=try await network.submit(submission)
            }
            try await accept(receipt,pending:pending)
            feedback(.confirmed)
        }
        catch{errorMessage=error.localizedDescription}
    }
    func cancelPendingExecution() async {
        guard !financialBusy,let pending=pendingExecution else{return}
        financialBusy=true;defer{financialBusy=false}
        do {
            try await network.cancel(actionHash:pending.actionHash)
            try LocalSecrets.delete(configuration.stateKey("pending-execution"));pendingExecution=nil
        }catch{errorMessage=error.localizedDescription}
    }
    func registerIdentity(label:String) async {
        guard !financialBusy,let owner=wallet.ownerAddress,let agent=wallet.agentAddress else{return}
        financialBusy=true;stopVoice();sensors.stopCapture();defer{financialBusy=false}
        do {
            let nonce=CanonicalBytes.hexString(try LocalSecrets.random32())
            let expiresAt=UInt64(Date().timeIntervalSince1970)+600
            let signature=try await wallet.signName(label:label,nonce:nonce,expiresAt:expiresAt)
            let registered=try await network.claimName(label:label,owner:owner,agent:agent,signature:signature,nonce:nonce,expiresAt:expiresAt)
            let resolved=try await network.identity(name:registered.name)
            guard resolved.address.lowercased()==agent.lowercased(),resolved.owner.lowercased()==owner.lowercased() else{throw ProductError.invalidResponse}
            try LocalSecrets.write(resolved,key:configuration.stateKey("mate-identity"));identity=resolved
        }catch{errorMessage=error.localizedDescription}
    }
}
