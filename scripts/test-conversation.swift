// Compile with production ConversationService, ShopPlanner, AppConfiguration and LocalSecrets.
// Canned sentences only. This executable never loads configuration, wallets or Keychain values.
import Foundation
import FoundationModels
import MateCore

@main struct ConversationAcceptance {
 static func main() async {
  let service=ConversationService()
  if let reason=await service.availability(){print(reason);exit(2)}
  var history=""
  var failures=0
  for (prompt,language,expected) in [("覚えておいて。机の上のマグカップは青色です。","日本語",""),("さっきのマグカップは何色だった？","日本語","青"),("Mac miniをAmazonで買って","日本語",""),("今日は会議が長くて、ちょっと疲れた。","日本語",""),("どうして疲れたって言ったか覚えてる？","日本語","会議"),("Hello, how are you?","English",""),("今日は会議が長くて疲れた。","日本語",""),("Can you answer in English now?","English","")] {
   do {
    let reply=try await service.reply(to:prompt,history:history,observations:"",notes:"",replyLanguage:language)
    var valid = !reply.text.isEmpty && (expected.isEmpty || reply.text.contains(expected))
    if prompt.contains("Amazon") {
     valid = valid && ["できません","できない","買えない","買えません","対応していません","未対応","行えません","行えない"].contains{reply.text.contains($0)}
      && !["注文しました","購入しました","購入は完了"].contains{reply.text.contains($0)}
      && ["用途","使","予算","構成"].contains{reply.text.contains($0)}
    }
    if language == "English" {valid = valid && reply.text.range(of:"[ぁ-んァ-ン一-龥]",options:.regularExpression) == nil}
    print("\(valid ? "PASS" : "FAIL") | \(prompt) | \(reply.text)")
    if !valid { failures += 1 }
    history += "\nUser: \(prompt)\nMate: \(reply.text)"
   } catch {print("FAIL | \(prompt) | \(error)");failures += 1}
  }
  print("On-device conversation and deterministic purchase refusal: \(8-failures)/8 checks passed. Public canned inputs only.")
  exit(failures == 0 ? 0:1)
 }
}
