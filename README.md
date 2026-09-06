# ZeroKey Mate

**Your companion. Your rules.**

iPhoneとDockKitスタンドで使う、端末内で会話する相棒です。外部へ翻訳・要約を依頼するときは、送る文章・提供者・宛先・料金を確認してから、承認済みの条件を満たすProveKit証明と限定された実行署名を送ります。決済はSepoliaのテストUSDC専用です。

## 起動

Apple Silicon Mac、Xcode 26以降、Node.js 22.16以降の22系または24系が必要です。XcodeGenと固定版Verityの公開ソースはプロジェクト内の `.tools/` に取得します。

```sh
npm ci --ignore-scripts
npm run configure          # 既存の .env は上書きしません
make test
make build-ios
./mate --simulator
```

画面・会話・カメラの開始にウォレットや決済の設定は不要です。会話にはApple Intelligence対応端末と利用可能な端末内モデルが必要です。カメラは設定の「開始」、マイクは「話す」で初めて起動します。「続けて話す」は個別に有効化した場合だけ、開始後の返答に続いて音声入力を再開します。

実機では `make project` 後に `apps/ios/ZeroKeyMate.xcodeproj` を開き、Signing Teamを設定して実行します。設定済みなら `MATE_DEVELOPMENT_TEAM=チームID ./mate --device UDID` も使えます。DockKitの接続・追尾は実機でのみ検証できます。

## 外部への依頼

[セットアップ](docs/setup.md)に従い、Privy、MateVault、ProveKit、ENSv2、The Graph、専門モデルを設定します。秘密値は無視対象の `.env` に保存します。

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

今回の実行結果と残る実機・外部接続の確認は [検証記録](docs/validation.md) に記載します。ビルドやローカルチェーンの検査は、実機DockKit・ライブ決済・スポンサー提出条件の検証を代替しません。

## 境界と出典

公開出典と依存ライセンスは [SOURCES](docs/SOURCES.md)、信頼条件は [architecture](docs/architecture.md)、実機確認は [device-checklist](docs/device-checklist.md) に記録します。無関係な非公開コードは実装元にしません。正式なクリーンルーム監査の認証ではありません。

ProveKitはポリシー適合性を証明します。クラウドの映像・音声の暗号化や実世界の本人確認は行いません。現行契約はオフチェーン検証器の署名を信頼します。カード認証・任意のコントラクト操作・本番資金は対象外です。Apache-2.0 [LICENSE](LICENSE) を維持します。
