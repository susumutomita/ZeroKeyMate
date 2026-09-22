import Foundation
import FoundationModels
import MateCore

struct WebSearchAnswer: Sendable {
    let text: String
    let result: WebSearchResult?
}

actor WebSearchConversation {
    private let provider:any WebSearchProviding
    private let summarizer:any SearchSummarizing
    init(provider:any WebSearchProviding=WebSearchAccess.shared,summarizer:any SearchSummarizing=LocalSearchSummary()) {
        self.provider=provider;self.summarizer=summarizer
    }
    func reply(to input:String,japanese:Bool) async throws -> WebSearchAnswer? {
        guard let query=WebSearchIntent.query(input) else {return nil}
        guard WebSearchIntent.isSafeQuery(query) else {
            return .init(text:japanese ? "公開情報の検索語を短く教えてください。名前や暗証番号などの個人情報は含めないでください。":"Please give me a short public search topic without personal details or secrets.",result:nil)
        }
        do {
            let result=try await provider.search(query:query,japanese:japanese)
            try Task.checkCancellation()
            guard !result.sources.isEmpty else {
                return .init(text:japanese ? "検索しましたが、答えの根拠になる情報が見つかりませんでした。検索語を変えてみてください。":"I searched but found no usable evidence. Try a different search topic.",result:result)
            }
            var answer:String?
            do {answer=try await summarizer.summarize(result,japanese:japanese)}
            catch {try Task.checkCancellation()}
            try Task.checkCancellation()
            if let answer {return .init(text:answer,result:result)}
            // If evidence cannot support an answer, expose the links without
            // speaking unverified page text (including embedded instructions).
            let text=japanese
                ? "検索結果は見つかりましたが、答えを確認できませんでした。会話画面の出典をご確認ください。"
                : "I found sources, but couldn't confirm an answer. You can check the source links in Conversation."
            return .init(text:text,result:result)
        } catch is CancellationError {throw CancellationError()}
        catch {
            try Task.checkCancellation()
            let message:String
            switch error as? WebSearchError {
            case .disabled: message=japanese ? "Web検索はまだオフです。設定の「Web検索」でBraveのAPIキーを登録すると調べられます。今の情報を推測では答えません。":"Web search is off. Add your Brave API key in Settings → Web search. I can't confirm current information without searching."
            case .credentials: message=japanese ? "検索APIキーを確認できませんでした。設定の「Web検索」で更新してください。":"The search API key wasn't accepted. Update it in Settings → Web search."
            case .quota: message=japanese ? "検索の利用上限に達したか、サービスが混み合っています。時間を置いてもう一度試してください。":"Search is at its usage limit or busy. Please try again later."
            default: message=japanese ? "今はWeb検索の情報を取得できませんでした。確認できないので推測では答えません。":"I couldn't retrieve web results right now, so I can't confirm the answer."
            }
            return .init(text:message,result:nil)
        }
    }
}
