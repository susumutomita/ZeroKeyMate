import Foundation
import FoundationModels
import MateCore

struct ConversationReply:Sendable {
    let text:String
    let service:MateService?
    let disclosure:String
}

enum ConversationFailure: Error, Sendable, Equatable {
    case responseBlocked
    init?(modelError: Error) {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *), let error=modelError as? LanguageModelError,
           case .guardrailViolation = error { self = .responseBlocked; return }
        #endif
        guard let error=modelError as? LanguageModelSession.GenerationError,
              case .guardrailViolation = error else{return nil}
        self = .responseBlocked
    }
}

protocol ConversationResponding:Sendable {
    func availability() async -> String?
    func prepare(replyLanguage:String,notes:String) async
    func reply(to text:String,history:[ConversationTurn],observations:String,notes:String,replyLanguage:String) async throws -> ConversationReply
    func streamReply(to text:String,history:[ConversationTurn],observations:String,notes:String,replyLanguage:String,
                     onPartial:@escaping @Sendable (String) async -> Void) async throws -> ConversationReply
}

extension ConversationResponding {
    func prepare(replyLanguage:String,notes:String) async {}
    func streamReply(to text:String,history:[ConversationTurn],observations:String,notes:String,replyLanguage:String,
                     onPartial:@escaping @Sendable (String) async -> Void) async throws -> ConversationReply {
        let response=try await reply(to:text,history:history,observations:observations,notes:notes,replyLanguage:replyLanguage)
        try Task.checkCancellation()
        await onPartial(response.text)
        return response
    }
}

actor ConversationService:ConversationResponding {
    private let local=LocalConversationSession()
    func availability() -> String? {
        switch SystemLanguageModel.default.availability {
        case .available:return nil
        case .unavailable(.deviceNotEligible):return "This device does not support on-device conversation. Use an Apple Intelligence-compatible iPhone."
        case .unavailable(.appleIntelligenceNotEnabled):return "Enable Apple Intelligence in Settings. Conversation will not fall back to the cloud."
        case .unavailable(.modelNotReady):return "The on-device conversation model is being prepared. Try again after the model download finishes."
        case .unavailable:return "The on-device conversation model is unavailable. Nothing is automatically sent to the cloud."
        }
    }
    func reply(to text:String,history:[ConversationTurn],observations:String,notes:String,replyLanguage:String) async throws -> ConversationReply {
        try await streamReply(to:text,history:history,observations:observations,notes:notes,replyLanguage:replyLanguage,onPartial:{_ in})
    }
    func prepare(replyLanguage:String,notes:String) async {
        guard availability()==nil,
              SystemLanguageModel.default.supportsLocale(Locale(identifier:replyLanguage == "日本語" ? "ja_JP":"en_US")) else{return}
        await local.prepare(replyLanguage:replyLanguage,notes:notes)
    }
    func streamReply(to text:String,history:[ConversationTurn],observations:String,notes:String,replyLanguage:String,
                     onPartial:@escaping @Sendable (String) async -> Void) async throws -> ConversationReply {
        try Task.checkCancellation()
        guard !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,text.utf8.count<=8_000 else {throw ProductError.invalidResponse}
        if let remembered=ConversationMemory.reply(to:text,history:history,language:replyLanguage) {
            await onPartial(remembered)
            try Task.checkCancellation()
            return ConversationReply(text:remembered,service:nil,disclosure:"")
        }
        if let recalled=PurchaseConversation.recall(input:text,history:history,replyLanguage:replyLanguage) {
            await onPartial(recalled)
            try Task.checkCancellation()
            return ConversationReply(text:recalled,service:nil,disclosure:"")
        }
        // Shopping results belong to the checkout's verified state, never free text.
        // Keep a misunderstood explicit purchase out of conversational generation.
        if !ShopPlanner.isLanguageTask(text), ShopPlanner.isCurrentPurchaseRequest(text) {
            try Task.checkCancellation()
            let message = replyLanguage == "日本語"
                ? "その購入はこの会話から実行できません。予算はどれくらいですか？"
                : "I can't make that purchase in this conversation. What budget do you have in mind?"
            await onPartial(message)
            try Task.checkCancellation()
            return ConversationReply(text:message,service:nil,disclosure:"")
        }
        if let reason=availability(){throw ProductError.unavailable(reason)}
        guard SystemLanguageModel.default.supportsLocale(Locale(identifier:replyLanguage == "日本語" ? "ja_JP":"en_US")) else {
            throw ProductError.unavailable("The on-device model does not support this conversation language yet.")
        }
        do {
            let answer=try await local.streamReply(to:text,history:history,observations:observations,
                notes:notes,replyLanguage:replyLanguage,onPartial:onPartial)
            return ConversationReply(text:answer,service:nil,disclosure:"")
        } catch {
            if let failure=ConversationFailure(modelError:error){throw failure}
            if let failure=error as? LocalConversationSession.Failure {
                switch failure {
                case .busy:throw ProductError.busy
                case .invalidResponse:throw ProductError.invalidResponse
                }
            }
            throw error
        }
    }
}
