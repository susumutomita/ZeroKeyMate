import AVFoundation
import Combine
import Foundation
import MateCore
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

@MainActor
final class CompanionModel:ObservableObject {
    enum Sheet:String,Identifiable {case conversation,settings,rules,wallet,identity,activity,disclosure,localProof;var id:String{rawValue}}
    @Published var sheet:Sheet?
    @Published var errorMessage:String?
    @Published private(set) var messages:[ConversationMessage]=[]
    @Published private(set) var thinking=false
    @Published private(set) var financialBusy=false
    @Published private(set) var executionStatus:String?
    @Published private(set) var modelUnavailable:String?
    @Published private(set) var proofUnavailable:String? = "Checking proof runtime."
    @Published private(set) var mandate:StoredMandate?
    @Published private(set) var spent:UInt64=0
    @Published private(set) var account:AccountState?
    @Published private(set) var identity:MateIdentity?
    @Published private(set) var receipts:[ExecutionReceipt]=[]
    @Published private(set) var providers:[ServiceProvider]=[]
    @Published private(set) var discoveryEvidence:String?
    @Published private(set) var discovering=false
    @Published private(set) var lastProofMilliseconds:Int?
    @Published private(set) var pendingExecution:PendingExecution?
    @Published var draft:DisclosureDraft? { didSet { requestGeneration = UUID() } }
    @Published var localNotes=""
    @Published var readAloud=true
    @Published var continuousConversation=false {
        didSet{if !continuousConversation{stopVoice()}}
    }
    @Published private(set) var voiceSessionActive=false
    @Published var sleeping=false
    let configuration:AppConfiguration
    let sensors=MateModel()
    let voice=VoiceService()
    let wallet:WalletService
    private let conversation=ConversationService()
    // A single actor serializes native work across payment and offline screens.
    let proofs=ProofService()
    private let network:NetworkService
    private let rpc:EthereumRPC
    private var conversationTask:Task<Void,Never>?
    private var conversationGeneration:UInt64=0
    private var requestGeneration=UUID()
    private var started=false
    private var foreground=true
    private var notifications=Set<AnyCancellable>()

    init(configuration:AppConfiguration=AppConfiguration.load()) {
        self.configuration=configuration
        wallet=WalletService(configuration:configuration)
        network=NetworkService(configuration:configuration)
        rpc=EthereumRPC(url:configuration.rpcURL)
        voice.onFinal={[weak self] text in self?.send(text)}
        voice.onPlaybackFinished={[weak self] in self?.resumeListening()}
        voice.onInputInterrupted={[weak self] in self?.stopVoice()}
        sensors.onDetach={[weak self] in self?.stopVoice()}
        NotificationCenter.default.publisher(for:AVAudioSession.interruptionNotification)
            .receive(on:DispatchQueue.main).sink{[weak self] _ in self?.stopVoice()}.store(in:&notifications)
        NotificationCenter.default.publisher(for:AVAudioSession.mediaServicesWereResetNotification)
            .receive(on:DispatchQueue.main).sink{[weak self] _ in self?.stopVoice()}.store(in:&notifications)
    }
    func start() async {
        guard !started else{return};started=true
        modelUnavailable=await conversation.availability()
        do{try await proofs.prepare();proofUnavailable=nil}catch{proofUnavailable=error.localizedDescription}
        do {
            mandate=try LocalSecrets.read(StoredMandate.self,key:"active-mandate")
            if let mandate{_=try mandate.policy.material()}
            identity=try LocalSecrets.read(MateIdentity.self,key:"mate-identity")
            receipts=try LocalSecrets.read([ExecutionReceipt].self,key:"receipts") ?? []
            pendingExecution=try LocalSecrets.read(PendingExecution.self,key:"pending-execution")
            localNotes=try LocalSecrets.read(String.self,key:"local-notes") ?? ""
            if configuration.walletConfigured{try await wallet.restore()}
        }catch{errorMessage=error.localizedDescription}
    }
    private func cancelConversation() {
        conversationGeneration &+= 1
        conversationTask?.cancel();conversationTask=nil;thinking=false
    }
    func setForeground(_ active:Bool) {
        foreground=active;sensors.setForeground(active)
        if !active{requestGeneration=UUID();stopVoice();cancelConversation()}
    }
    func stopVoice(){voiceSessionActive=false;voice.stop()}
    private func resumeListening() {
        Task{[weak self] in
            guard let self,self.voiceSessionActive,self.foreground,!self.sleeping,!self.thinking,!self.financialBusy else{return}
            await self.voice.start()
            if !self.voice.listening{self.voiceSessionActive=false}
        }
    }
    func rest(){requestGeneration=UUID();sleeping=true;stopVoice();sensors.stopCapture();cancelConversation()}
    func wake(){sleeping=false}
    func saveNotes() {
        guard localNotes.utf8.count<=2_000 else{errorMessage="Keep notes within 2,000 bytes.";return}
        do{try LocalSecrets.write(localNotes,key:"local-notes")}catch{errorMessage=error.localizedDescription}
    }
    func clearConversation(){cancelConversation();stopVoice();messages=[];draft=nil}
    func send(_ text:String) {
        let input=text.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !thinking,!financialBusy,!input.isEmpty,foreground else{return}
        guard input.count<=2_200 else{errorMessage="Keep each message within 2,200 characters.";return}
        sleeping=false;voice.stop();thinking=true
        conversationGeneration &+= 1
        let generation=conversationGeneration
        let history=messages.suffix(8).map{($0.isUser ? "User: ":"Mate: ")+$0.text}.joined(separator:"\n")
        messages.append(ConversationMessage(isUser:true,text:input));messages=Array(messages.suffix(40))
        let notes=localNotes
        conversationTask=Task{[weak self] in
            guard let self else{return}
            defer{
                if self.conversationGeneration==generation {
                    self.thinking=false
                    if !self.voice.speaking{self.resumeListening()}
                }
            }
            do {
                let response=try await self.conversation.reply(to:input,history:history,
                    observations:self.sensors.currentObservation,notes:notes)
                try Task.checkCancellation()
                guard self.foreground,self.conversationGeneration==generation else{return}
                self.messages.append(ConversationMessage(isUser:false,text:response.text))
                if let service=response.service,!response.disclosure.isEmpty {
                    self.draft=DisclosureDraft(service:service,text:response.disclosure)
                }
                if self.readAloud{self.voice.speak(response.text)}
            }catch is CancellationError{}catch{
                if self.conversationGeneration==generation{self.stopVoice();self.errorMessage=error.localizedDescription}
            }
        }
    }
    func toggleVoice() async {
        if voiceSessionActive{stopVoice();cancelConversation()}
        else if voice.requestingPermission{stopVoice()}
        else if voice.listening{let text=voice.finish();send(text)}
        else{
            guard !thinking,!financialBusy,foreground else{return};sleeping=false
            voiceSessionActive=continuousConversation
            await voice.start()
            if !voice.listening{voiceSessionActive=false}
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
            providers=response.providers;discoveryEvidence="The Graph · block \(response.indexedBlock)"
            if providers.isEmpty{throw ProductError.unavailable("No active provider meets these requirements. No preset alternative will be substituted.")}
        }catch{errorMessage=error.localizedDescription}
    }
    func refreshAccount() async {
        guard let owner=wallet.ownerAddress else{return}
        do {
            account=try await network.account(owner:owner)
            if let mandate {
                let state=try await network.mandate(id:mandate.id)
                guard state.owner.lowercased()==mandate.grant.owner.lowercased(),
                      state.agent.lowercased()==mandate.grant.agent.lowercased(),
                      state.policyHash.lowercased()==mandate.grant.policyHash.lowercased(),let value=UInt64(state.spent) else{throw ProductError.invalidResponse}
                spent=value
                if state.revoked || state.validUntil<=UInt64(Date().timeIntervalSince1970) {
                    try LocalSecrets.delete("active-mandate");self.mandate=nil
                }
            }
        }catch{errorMessage=error.localizedDescription}
    }
    func authorize(budget:String,translation:Bool,summary:Bool,hours:Int) async {
        guard !financialBusy else{return}
        guard mandate == nil else{errorMessage="Revoke the current mandate before changing its terms.";return}
        guard let owner=wallet.ownerAddress,let agent=wallet.agentAddress,configuration.paymentsConfigured else{
            errorMessage="Set up your wallet and Sepolia connection first.";return
        }
        financialBusy=true;stopVoice();sensors.stopCapture();defer{financialBusy=false;executionStatus=nil}
        do {
            guard try LocalSecrets.read(PendingGrant.self,key:"pending-grant") == nil else{
                throw ProductError.unavailable("A mandate is awaiting confirmation. Recover it and check its status first.")
            }
            guard (1...24).contains(hours) else{throw MandateError.invalidPolicy}
            let policy=try PrivatePolicy(budget:TokenAmount(decimal:budget).units,
                services:(translation ? 1:0)|(summary ? 2:0),salt:LocalSecrets.random32())
            let state=try await network.account(owner:owner)
            let grant=try MandateGrant(owner:owner,agent:agent,policyHash:LocalSecrets.hash(policy.material()),
                validUntil:UInt64(Date().timeIntervalSince1970)+UInt64(hours*3600),nonce:state.nonce)
            executionStatus="Verifying owner approval"
            let signature=try await wallet.signGrant(grant)
            let pending=PendingGrant(grant:grant,policy:policy,signature:signature)
            try LocalSecrets.write(pending,key:"pending-grant")
            executionStatus="Registering the mandate on Sepolia"
            try await finishGrant(pending)
        }catch{errorMessage=error.localizedDescription}
    }
    private func finishGrant(_ pending:PendingGrant) async throws {
        let receipt=try await network.register(grant:pending.grant,signature:pending.signature)
        _=try await rpc.confirm(hash:receipt.transactionHash)
        let state=try await network.mandate(id:receipt.mandateId)
        guard state.owner.lowercased()==pending.grant.owner.lowercased(),state.agent.lowercased()==pending.grant.agent.lowercased(),
              state.policyHash.lowercased()==pending.grant.policyHash.lowercased(),state.validUntil==pending.grant.validUntil,
              !state.revoked,let value=UInt64(state.spent) else{throw ProductError.invalidResponse}
        let stored=StoredMandate(id:receipt.mandateId,grant:pending.grant,policy:pending.policy)
        try LocalSecrets.write(stored,key:"active-mandate");try LocalSecrets.delete("pending-grant")
        mandate=stored;spent=value
    }
    func recoverGrant() async {
        guard !financialBusy else{return};financialBusy=true;defer{financialBusy=false}
        do {
            guard let pending=try LocalSecrets.read(PendingGrant.self,key:"pending-grant") else{
                throw ProductError.unavailable("There is no pending mandate.")
            }
            try await finishGrant(pending)
        }catch{errorMessage=error.localizedDescription}
    }
    func fund(_ operation:WalletService.FundingOperation) async {
        guard !financialBusy else{return}
        financialBusy=true;stopVoice();sensors.stopCapture();defer{financialBusy=false;executionStatus=nil}
        do {
            executionStatus="Verifying signature"
            let hash=try await wallet.send(operation)
            executionStatus="Waiting for Sepolia confirmation"
            _=try await rpc.confirm(hash:hash)
            if case .revoke=operation{try LocalSecrets.delete("active-mandate");mandate=nil}
            await refreshAccount()
        }catch{errorMessage=error.localizedDescription}
    }
    func execute(payload:String,provider:ServiceProvider) async {
        guard !financialBusy else{return}
        guard foreground,!sleeping else{errorMessage="Wake Mate before making a request.";return}
        if let reason=proofUnavailable{errorMessage=reason;return}
        guard pendingExecution == nil else{errorMessage="A transaction is awaiting confirmation. Check Activity before retrying to avoid duplicate execution.";return}
        guard let approvedDraft=draft, let stored=mandate,let service=MateService(rawValue:provider.service),let amount=UInt64(provider.price),
              approvedDraft.service==service,
              providers.contains(provider),!payload.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
              payload.utf8.count<=8_000 else{errorMessage="Check the mandate, provider and text to share.";return}
        let ticket=requestGeneration
        func checkApproval() throws {
            guard foreground, !sleeping, requestGeneration==ticket, draft?.id==approvedDraft.id else{throw ProductError.cancelled}
        }
        financialBusy=true;stopVoice();defer{financialBusy=false;executionStatus=nil}
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
            executionStatus="Generating a proof on this iPhone"
            let proof=try await proofs.prove(policy:stored.policy,action:action,chainID:configuration.chainID,vault:configuration.vault)
            try checkApproval()
            lastProofMilliseconds=proof.elapsedMilliseconds
            guard proof.policyHash.lowercased()==stored.grant.policyHash.lowercased() else{throw ProductError.invalidResponse}
            executionStatus="Signing with the restricted execution key"
            let signature=try await wallet.signAction(hash:proof.actionHash)
            try checkApproval()
            let submission=ExecutionSubmission(action:action,agentSignature:signature,proof:proof.bytes.base64EncodedString(),payload:payload,providerId:provider.id)
            let pending=PendingExecution(actionHash:proof.actionHash,proofHash:proof.proofHash,createdAt:Date(),submission:submission)
            try LocalSecrets.write(pending,key:"pending-execution");pendingExecution=pending
            executionStatus="Sending approved text and confirming execution"
            let receipt=try await network.execute(action:action,signature:signature,proof:proof.bytes,payload:payload,providerID:provider.id)
            try await accept(receipt,pending:pending)
            if requestGeneration==ticket {
                messages.append(ConversationMessage(isUser:false,text:receipt.result));draft=nil;sheet = .activity
            }
        }catch{errorMessage=error.localizedDescription}
    }
    private func accept(_ receipt:ExecutionReceipt,pending:PendingExecution) async throws {
        guard receipt.actionHash.lowercased()==pending.actionHash.lowercased(),receipt.proofHash.lowercased()==pending.proofHash.lowercased(),
              let value=UInt64(receipt.spentAfter) else{throw ProductError.invalidResponse}
        try await rpc.confirmExecution(receipt,pending:pending,vault:configuration.vault)
        spent=value;receipts.removeAll{$0.id==receipt.id};receipts.insert(receipt,at:0);receipts=Array(receipts.prefix(30))
        try LocalSecrets.write(receipts,key:"receipts");try LocalSecrets.delete("pending-execution");pendingExecution=nil
    }
    func recoverExecution() async {
        guard !financialBusy,let pending=pendingExecution else{return}
        financialBusy=true;defer{financialBusy=false}
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
        }
        catch{errorMessage=error.localizedDescription}
    }
    func cancelPendingExecution() async {
        guard !financialBusy,let pending=pendingExecution else{return}
        financialBusy=true;defer{financialBusy=false}
        do {
            try await network.cancel(actionHash:pending.actionHash)
            try LocalSecrets.delete("pending-execution");pendingExecution=nil
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
            try LocalSecrets.write(resolved,key:"mate-identity");identity=resolved
        }catch{errorMessage=error.localizedDescription}
    }
}
