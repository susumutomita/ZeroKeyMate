# ZeroKey Mate

**Your companion. Your rules.**

[English README](../README.md) · [ETHGlobal提出文案](submission.md) · [デモ台本](demo.md) · [開発履歴・AI利用](development-history.md)

iPhoneとDockKitスタンドで使う、端末内で会話する相棒です。外部へ翻訳・要約を依頼するときは、送る文章・提供者・宛先・料金を確認してから、承認済みの条件を満たすProveKit証明と限定された実行署名を送ります。決済はArc TestnetのテストUSDCが中心で、既存のSepolia設定にも対応します。公開ネットワークでの一連の実行は未検証です。

現在はローカルで証明・実契約・HTTP・実モデル・復元を確認したプロトタイプです。ローカル決済はAnvilでのシミュレーションです。実機DockKitと外部サービスのライブ接続は未確認です。提出対象の実装は [PR #12のブランチ](https://github.com/susumutomita/ZeroKeyMate/tree/codex/complete-local-runtime) にあります。新規取得の手順は [English README](../README.md#run-the-app) を参照してください。

製品全体の実装も完了ではありません。処理中止の統一、一括起動、アプリ内ペアリング、会話からの設定操作、スタンド演出などが [既存バックログ](validation.md#remaining-product-implementation) に残ります。


## 何に使うのか

**あなたが決めた予算と許可の範囲で、外部AIに仕事を頼む机上の相棒**です。普段の会話はiPhone内で処理し、外部に依頼するときだけ文章・提供者・支払先・今回の料金を確認します。

例：「この日本語の会議メモを英訳して。今夜まで翻訳だけ許可し、合計5テストUSDCまで」。現在は **Your rules** で条件を設定する形です。会話だけで条件設定から実行まで完結する体験は未完成です。

| ユースケース | 使い方・価値 |
| --- | --- |
| 海外の同僚に会議メモを渡す | 必要な文章だけ翻訳に送り、会話履歴や非公開の予算は渡さない |
| 長いメモの要点を知る | 選んだ文章と料金を確認して要約を依頼する |
| 依頼中に通信が切れる | Activityで同じ依頼を復元し、二重払いを避ける。ローカル統合テストで確認済み |

BelkinのDockKit対応スタンドは相手を向く机上の相棒としての体験、iPhone内AIは日常会話、クライアントZKは非公開ルールへの適合証明、コントラクトは署名・期限・失効・二重実行の検査とテスト送金を担います。スタンドなしでも証明と支払いは成立します。

ZKは音声・映像の暗号化や翻訳品質の保証ではありません。依頼先には承認した文章が渡り、支払額・宛先は公開されます。現在は非公開ルールの適合性について証明検証サーバーを信頼します。実機スタンド、iPhoneでの証明性能、一連の実機・公開テストネット動作は未検証です。

締切と残作業は [提出までのスケジュール](schedule.md) を参照してください。

## 起動

Apple Silicon Mac、Xcode 26以降、Node.js 22.16以降の22系または24系が必要です。XcodeGenと固定版Verityの公開ソースはプロジェクト内の `.tools/` に取得します。

```sh
npm ci --ignore-scripts
npm run configure          # 既存の .env は上書きしません
make test
```

起動先を選ぶ場合（`1`：Simulator、`2`：実機iPhone、`q`：キャンセル（メニュー表示は英語））：

```sh
make start
```

選択メニューを省略して直接起動する場合：

```sh
make start-simulator  # Simulator
make start-device     # 実機iPhone
```

画面・会話・カメラの開始にウォレットや決済の設定は不要です。会話にはApple Intelligence対応端末と利用可能な端末内モデルが必要です。アプリ表示と音声入出力は英語です。カメラは Settings の Start camera、マイクは Talk で初めて起動します。Continuous conversationは個別に有効化した場合だけ、開始後の返答に続いて音声入力を再開します。

実機はUSB接続・ロック解除・Macの信頼・Developer Modeの有効化が必要です。接続済みiPhoneと署名用Teamが1つずつなら自動選択します。複数ある場合は `MATE_DEVICE_UDID=UDID MATE_DEVELOPMENT_TEAM=チームID make start` で指定します。署名用証明書がない場合は `make project` 後に `apps/ios/ZeroKeyMate.xcodeproj` を開き、XcodeでApple AccountとSigning Teamを設定してください。DockKitの接続・追尾は実機でのみ検証できます。APIと専門サービスは別途起動します。

## 外部への依頼

[セットアップ](setup.md)に従い、Privy、MateVault、ProveKit、ENSv2、The Graph、専門モデルを設定します。秘密値は無視対象の `.env` に保存します。

```sh
npm run api               # 委任・探索・証明検証・支払・復元API
npm run provider          # 別ターミナル。実際のOllamaモデルで翻訳／要約
```

1. ウォレット画面でPrivyにログインし、所有者とMateのウォレットを準備します。
2. テストUSDCの承認と預け入れをそれぞれ確認します。
3. 「あなたのルール」で予算・許可する仕事・期限を承認します。
4. 依頼画面で文章を編集し、The Graph・ENS・実際の見積もりから取得した提供者を選びます。
5. iPhoneが証明を生成します。専門サービスは仕事を準備し、契約の支払記録を確認してから結果を返します。
6. 切断時は履歴から同じ依頼を復元します。未受信なら保存済みの同じ署名・識別子で再送します。未送金の取り消しはサーバーへの永続記録を確認してから解除します。

予算・ソルト・端末内の会話履歴は送信しません。承認した文章は専門サービスに開示され、復元用の暗号化記録に保存されます。送金先・金額は公開情報です。

## 検証

```sh
make test                 # Swift + Node
make build-ios            # Simulator SDKビルド
make build-device         # 実機SDKビルド。署名なし
make test-contracts       # Anvil上の実契約。ローカル決済シミュレーション
make proofs               # Rustが必要。公開版ProveKitで回路生成・正常／異常条件を検査
cargo +nightly-2026-03-04 build --release --locked --manifest-path services/verifier/Cargo.toml
npm run test:proofs        # Rust検証器と実際の証明によるAPI境界の検査
npm run test:local         # 実証明・HTTP・契約をつなぐローカル決済シミュレーション
make native-runtime       # 公開ソースからiOSのProveKitをビルド
./mate --verify           # 実ランタイムと回路が必要。Simulatorで証明・Keychain・UIを検査
./mate --readiness         # 設定と未検証項目。製品の完成証明ではありません
```

通常のビルドは証明ランタイムなしでも起動できますが、その場合は証明生成・外部実行を利用できません。`make native-runtime` と `make proofs` の後で再ビルドすると実ランタイムを組み込みます。通常のセットアップは期限付きのCI成果物に依存しません。

今回の実行結果と残る実機・外部接続の確認は [検証記録](validation.md) に記載します。ビルドやローカルチェーンの検査は、実機DockKit・ライブ決済・スポンサー提出条件の検証を代替しません。

## 境界と出典

公開出典と依存ライセンスは [SOURCES](SOURCES.md)、信頼条件は [architecture](architecture.md)、実機確認は [device-checklist](device-checklist.md) に記録します。無関係な非公開コードは実装元にしません。正式なクリーンルーム監査の認証ではありません。

ProveKitはポリシー適合性を証明します。クラウドの映像・音声の暗号化や実世界の本人確認は行いません。現行契約はオフチェーン検証器の署名を信頼します。カード認証・任意のコントラクト操作・本番資金は対象外です。Apache-2.0 [LICENSE](../LICENSE) を維持します。

## Arcと接続設定

`make dev` はAPI・専門サービスを起動してからシミュレーター／iPhoneを選びます。直接指定は `make dev-simulator` または `make dev-device`。Ctrl+Cで起動したサービスを停止します。アプリだけなら従来どおり `make start` を使えます。アプリの **Settings → Configure connection** でAPIと決済先を検証してKeychainへ保存できます。[Arc設定手順](arc-setup.md)を参照してください。Circleの規約同意・ログイン、Privy／The Graphの設定、テスト資金は別途必要です。

## 表示と音声の言語

初期表示は英語です。**Settings → Language → 日本語** で切り替えると、画面・証明の説明・アプリのエラー・音声入力・読み上げが日本語になります。**設定 → 言語 → English** で英語へ戻せます。選択は再起動後も保持します。言語変更時は音声・カメラ・生成中の会話を停止し、自動では再開しません。会話の返答も選択言語が基本ですが、明示的に別の言語を依頼できます。iOSや外部SDKが管理する許可画面などは端末側の言語設定に従います。
