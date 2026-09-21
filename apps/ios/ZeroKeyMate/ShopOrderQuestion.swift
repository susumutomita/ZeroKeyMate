import Foundation

enum ShopOrderQuestion {
    /// Read-only status questions are answered from checkout, before the local
    /// language model. Quoted/translation instructions remain language tasks.
    static func matches(_ input: String) -> Bool {
        guard !ShopPlanner.isLanguageTask(input) else { return false }
        let value = input.lowercased().filter { !$0.isWhitespace && !$0.isPunctuation }
        let exact = ["注文を確認して", "注文どうなった", "注文の状況を教えて", "checkmyorder", "checktheorder", "orderstatus"]
        if exact.contains(value) { return true }
        let japanese = #"^(?:(?:mate|メイト)[、\s]*)?(?:(?:購入|注文|支払い|決済|年齢確認|年齢の証明)(?:は|が)?(?:もう)?(?:完了|終わっ|済ん|でき)(?:した|して|しまし|て|た|い|る|ます|ました|です|か|の|ね|よ|ん|まだ)*|(?:(?:ビール|炭酸水|水)(?:は|を)|もう)?(?:買えた|買ってくれた|買ってきた)(?:の|か|です|ん|よ|ね)*)$"#
        let english = #"^(?:didyou(?:buy(?:my|the)?(?:beer|water|sparklingwater)|(?:complete|finish)(?:my|the)?(?:order|purchase|payment))|haveyou(?:bought(?:my|the)?(?:beer|water|sparklingwater)|(?:completed|finished)(?:my|the)?(?:order|purchase|payment))|is(?:my|the)?(?:order|purchase|payment|ageverification)(?:complete|completed|done|confirmed)|has(?:my|the)?(?:order|purchase|payment)(?:finished|completed)|(?:order|purchase|payment|ageverification)(?:complete|completed|done|status))(?:yet|already|now)?$"#
        return value.range(of: japanese, options: .regularExpression) != nil ||
            value.range(of: english, options: .regularExpression) != nil
    }
}

extension ShopCheckout.Phase {
    var purchaseAnswer: String {
        switch self {
        case .complete: return "Yes. Your test purchase is complete, and the payment is confirmed on Arc Testnet."
        case .proofFailed: return "Not yet. Your card was read, but age proof creation did not finish. No payment was sent."
        case .verificationFailed, .verifying: return "Not yet. Your age proof was created, but the store has not confirmed it. No payment was sent."
        case .paymentApproval: return "Not yet. Your order is ready, but it is waiting for you to approve the displayed payment."
        case .paying, .pending: return "Your payment is still unconfirmed. I will check the same order before reporting it complete."
        case .expired: return "No. The payment authorization expired unused. This order was not paid."
        case .card, .preparingCard, .readingCard, .proving: return "Not yet. Age verification has not finished, and no payment was sent."
        default: return "I cannot confirm a completed purchase. Please check the saved order."
        }
    }
}
