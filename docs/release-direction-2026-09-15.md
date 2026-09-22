# 正式版に向けた設計方針（2026-09-15）

目指す価値は、**話しかけると、許可した範囲でサービスを利用し、必要な属性だけを証明してくれる相棒**。専用のビール店舗はその最初の検証例にする。

この文書はリリース計画であり、以下の新規連携がすべて実装済みという意味ではない。2026-09-22の接続サービス画面・署名検証・中断復旧の実装状況は[外部x402](external-x402.md)を参照。公開仕様だけを調査対象とし、未公開のMynaWalletコードや開発中APIを取り込まない。

## 現在の基準点

- 実機で物理My Numberカードの認証、ローカル年齢証明、専用店舗での検証、Privyによる単発承認、Arc Testnetのx402決済が通った。詳細は[実機・決済記録](arc-live-status.md)。
- 年齢回路は実験的なProveKit Groth16バックエンド。証明書の失効確認は未対応、セットアップは単独実施。正式な本人確認基盤としての完成を示すものではない。
- `WalletService.signShopPayment` はArcの専用支払いに固定され、65バイトの署名を要求する。コントラクトウォレット署名の汎用アダプターではない。
- `AgeShopProtocol` と店舗の `protocol.mjs` はネットワーク・商品・年齢条件が固定。URLの差し替えだけでは任意店舗へ対応できない。
- 年齢検証はWorkerからAge Gateへの `eth_call`。送金と原子的ではなく、現行Age Gateはパーミッションバリデーターではない。
- 会話ストリーミングはPR #58でmainへ反映。iOS 26.7のiPhone 16 Proにbuild 9をインストール・起動確認済み。新モデルの準備状態や実際の音声応答時間は別途確認する。

## 体験

1. 利用者がMateへ依頼する。
2. 接続済みのサービスから、商品・実行内容・金額・支払い条件を得る。
3. 許可済みの範囲かを確認する。初回・予算超過・未対応条件は承認または説明を返す。
4. **年齢制限がある場合だけ**、受け入れ可能な年齢証明の条件を確認する。
5. 有効な証拠がなければマイナアプリなどの認証へ進み、端末で注文に結びついた証明を作る。
6. サービスの検証成功後、対応ウォレットで支払いを承認・実行する。
7. 決済結果と実行結果を区別して確認し、Mateが結果を説明する。タイムアウト時は同じ支払いを追跡する。

## 公開仕様から分かること

| 項目 | 確認結果 | Mateで必要な作業 |
| --- | --- | --- |
| x402 v2 | `PAYMENT-REQUIRED`、`PAYMENT-SIGNATURE`、`PAYMENT-RESPONSE`による支払いフローが公開されている | 専用注文とは独立したクライアント、対応条件の選択、署名前の検査 |
| コントラクトウォレット | EIP-1271を扱える経路があるが、トークン・SDK・facilitator・署名形式ごとに互換性が異なる | 65バイト固定を独立させる。実際のトークンとfacilitatorで署名の検証から決済まで確認 |
| MynaWallet | 公式プライバシーポリシーにWalletConnectの接続先dApp・署名要求を扱う機能の記載がある。一般提供SDKと予算委譲APIの条件は未確認 | 対応chain、typed-data署名メソッド、返却形式、権限制限を確認。WalletConnectの記載だけでx402決済を保証しない |
| デジタル認証サービス | マイナアプリとの同一端末連携、OIDC認証、署名APIが公開されている | サービス登録・鍵登録・検証体制・利用条件の確認 |
| スマホ搭載カード | スマホ単体の認証／署名機能は存在する | 既存の物理カード用証明書プロファイルとの相違を検証し、新しい回路・検証鍵が必要か判断 |

出典：[x402 v2仕様](https://github.com/x402-foundation/x402/blob/main/specs/x402-specification-v2.md)、[x402 wallet compatibility](https://docs.x402.org/advanced-concepts/wallet-compatibility)、[MynaWallet公式](https://www.mynawallet.co.jp/)、[デジタル認証サービス実装ガイド](https://developers.digital.go.jp/documents/auth-and-sign/implement-guideline/)、[スマートフォンのマイナンバーカード](https://www.digital.go.jp/policies/mynumber/smartphone-certification)。

調査はChatGPT Proで公開情報を整理し、採用する根拠を公式資料で再確認した。[MynaWalletの公式ポリシー](https://www.mynawallet.jp/privacy.html)は接続機能の存在を示すが、ZeroKeyMate向けSDKの互換性試験に代わるものではない。未公開コードや実利用者の情報は調査に提供していない。

### スマホ搭載カードの候補を分ける

- **マイナアプリ／デジタル認証サービス**：OIDCによるログインと、署名APIの結果は別。署名結果は下記のPF向け暗号化を前提にする。
- **Verify with Wallet**：Appleは日本のMy Numberカードと `PKIdentityNationalIDCardDescriptor` を公開している。利用権限の申請が必要で、標準フローはアプリが暗号文を受け取りサーバーで復号・検証する。20歳の閾値情報を取得できる条件、署名付き情報をZK入力に使える条件は要確認。属性を端末へ返すだけでは、サーバーが属性を受け取った事実はなくならない。[Apple公式ガイド](https://developer.apple.com/wallet/get-started-with-verify-with-wallet/)
- **PassKitのJPKI直接API**：`JPKIPassContents` と `Signature` / `Certificate` の公開型は存在する。APIが存在しないと断定しない。ただしアプリのアクセス権、証明書プロファイル、署名形式、失効確認、利用条件を確認するまでは物理カード回路への置換を約束しない。[JPKIPassContents](https://developer.apple.com/documentation/passkit/jpkipasscontents)、[署名と証明書](https://developer.apple.com/documentation/passkit/jpkipasscontents/signature)

直接APIの公開資料では、利用者証明用の認証に `systemBiometric` がある一方、署名用の認証は `password` が示される。すべての署名がFace IDだけで済むとは仮定しない。[利用者証明用](https://developer.apple.com/documentation/passkit/jpkipasscontents/useridentity-swift.struct/authenticationtype)、[署名用](https://developer.apple.com/documentation/passkit/jpkipasscontents/signingidentity-swift.struct/authenticationtype)

## 本人確認とZKの接続

ウォレットへのログイン成功は、そのウォレットを操作できることの根拠にはなるが、それだけで第三者に年齢を証明できるわけではない。ZKで隠す入力には、**信頼できる発行者が署名した年齢属性と、現在の利用者・注文への結びつき**が必要になる。

候補は次の二つ。最初から同じものとして扱わない。

- **政府署名の証拠を回路で検証する経路**：署名用証明書、注文への署名、証明書プロファイル、期限・失効状態を扱う。スマホ搭載証明書に、現在の物理カードと同じ年齢属性があるとは仮定しない。
- **本人確認事業者の署名付き属性証明を使う経路**：事業者が確認した `age_over_20` 等を、所有者への結びつき・期限・失効条件付きで発行し、端末でその署名を証明する。この場合、店舗は政府署名だけでなく、その発行事業者の確認結果を信頼する。

民間向け署名APIには署名値・署名用証明書を返す機能がある。ただし返却値は登録したプラットフォーム事業者向けJWEとして扱われるため、任意のiPhoneが直接復号できるわけではない。サービス用の復号秘密鍵をアプリに埋め込まない。認証事業者が情報を処理する構成にした場合、「カード情報は端末から一切出ない」という現在の物理カード経路の説明は再利用できない。

出典：[民間向けAPIの署名結果](https://developers.digital.go.jp/documents/auth-and-sign/authserver/)、[実装ガイド・署名用電子証明書と署名値の暗号化](https://developers.digital.go.jp/documents/auth-and-sign/implement-guideline/)。この接続方法は設計上の提案であり、MynaWalletが属性証明を発行することを確認したものではない。

単なる `verified: true`、自己申告DOB、真正性を証明できないJSONや画面キャプチャを回路に入れても、年齢の根拠にはならない。先に証拠の形式と信頼モデルを決め、その後に回路を設計する。証明方式を変えるだけでは解決しない。

## 最小のリリース順序と完了条件

### 1. 外部x402サービスを使えるTestFlight版

- 専用店舗の外に `PaymentRequest` / `PaymentProvider` / `PaymentReceipt` の境界を作る。
- 当初は1つの検証済みEVMネットワーク、`exact`、対応USDC、単発承認に限定する。対象を「任意のWebサイト」ではなく、利用条件が機械可読な接続サービスとする。
- 生の任意署名APIをLLMに渡さない。価格・通貨・chain・宛先・origin・resource・有効期限・注文／nonceを独立したコードで検査する。
- 2つ以上の独立したサービスで、支払い／キャンセル／タイムアウト復帰／再起動を実機検証する。支払い済みなのに結果が不明な状態で新しい署名を作らない。
- 年齢確認は別アダプターとし、通常サービス利用にカード認証を必須にしない。

### 2. MynaWallet接続

- 公開された接続インターフェースと対応chainを確認してからアダプターを実装する。
- typed-dataへの署名可否、EIP-1271形式、トークンでの検証、facilitatorでの受理を一組として検証する。WalletConnect対応の有無だけでは決済互換性を判断しない。
- 最初は一回ごとの承認を維持する。予算委譲は、上限・許可先・期限・失効・複数注文での合計消費を実行時に強制できる公開機構が確認できてから追加する。
- 署名の正しさの検査と、予算を消費する実行は別問題。検証を何度呼んでも二重消費せず、実行の並行競合でも予算を超えないことを確認する。

### 3. 必要時だけの年齢証明

- 公式Sandboxと検証用の属性で、利用者・端末・注文・発行者の結びつきを通して確認する。
- 別人、18〜19歳、期限切れ、失効、別注文への再利用を拒否する。20歳以上という具体的な条件を使い、「成人」という曖昧な条件に置き換えない。
- 店舗と証明書発行者の対応形式を合意する。x402対応だけで任意の年齢Proofを受理してくれるわけではない。
- 外部認証からMateへ戻り、元の注文を復元する。認証がキャンセルされたら決済しない。

### 4. 一般公開

実機の会話応答時間と停止・割り込み、連続購入の復旧、証明の信頼性、審査・運用条件を確認してから本番ネットワークへ進む。現行テストネット用の設定や単独セットアップをそのまま本番用に格上げしない。実資金・事業者契約・App Store公開は、対象と条件を具体化して実施する。

## 日本語動画

[台本](presentation/youtube-ja.json)と[生成スクリプト](../scripts/build-youtube-ja.py)から、ローカルVOICEVOXを使う日本語解説版を生成する。提出済みの本人音声版は保持する。新しい動画はYouTube向けで、提出済み動画の差し替えではない。

未来の連携は「未対応／構想」と明示し、12秒は1回のローカル処理表示値として説明する。既存実機映像は成功した複数テイクの編集で、今回の新しい実機計測ではない。音声クレジットは動画内と概要欄へ記載する。

音声出典・利用条件：[VOICEVOX利用規約](https://voicevox.hiroshiba.jp/term/)、[ずんだもん音源利用規約](https://zunko.jp/con_ongen_kiyaku.html)。
