# 検証記録 — 2026-09-06

APIと専門サービスの欠けていた実装、iOSの復元・停止操作、起動手順を補完しました。ローカルでの自動検査とiOS SDKビルドは成功しています。実機DockKitと外部サービスのライブ接続は未確認のため、製品全体の受け入れ完了とは扱いません。

検査時点の対象は `8d8b271` を基点とする作業ディレクトリの変更です。環境はApple Silicon、macOS 26.6.2、Xcode 26.6（17F113）、Node.js 24.14.1です。既存のApache-2.0 LICENSEと、別作業のschedulerファイルは変更していません。

## 実行した検査

| 検査 | 結果と範囲 |
| --- | --- |
| `make test SWIFT_TEST_FLAGS=--disable-sandbox` | 成功。Swift XCTest 19件、Node 22件。カメラの開始意図、承認データ、取引記録の照合、暗号化ジャーナル、取消・再送、HTTP認証、専門サービスの結果保留を検査 |
| `make test-contracts` | 成功、12件。実際のSolidity契約をAnvilで実行。署名・宛先等の改変、失効、再実行、残高分離、名前リゾルバーを検査。ローカル決済シミュレーション |
| `npm run test:proofs` | 成功、3件。実際のRust ProveKit検証器が正常な証明を受理し、証明改変と別取引への流用を拒否 |
| `npm run test:local` | 成功、1件。新しく生成した実際の証明 → HTTP API → MateVault → HTTP専門サービスの結果受領。APIとSQLite接続を閉じて再起動し、結果復元・同じ依頼の再送で残高が二重に減らないことも確認 |
| ProveKit CLI `prove` / `verify` | 正常な証明の新規生成・検証に成功。不正な6条件はすべて `Cannot satisfy constraint` で拒否 |
| Rust検証器の `cargo ... build --release --locked` | 成功。固定版ProveKit 1.0.1と保存したCargo.lockを使用 |
| `make build-ios` | 成功。実ProveKitランタイムをリンクしたarm64 Simulator SDKビルド |
| `make build-device` | 成功。実ProveKitランタイムをリンクしたarm64 iPhone SDKビルド。署名・インストールは未実施 |
| `MATE_PROOF_RUNTIME=source-only make build-ios` | 成功。証明ランタイムを含めない構成もビルド可能。証明機能は利用不可になる |
| `npm audit --audit-level=low` | 指摘0件。依存ライセンス・公開出典は別途 [SOURCES](SOURCES.md) に記録 |
| 差分・シェル・plist検査 | `git diff --check`、`bash -n`、`plutil -lint` 成功 |

自動テストは合計57件です。6種類の不正witness拒否はこの件数と別に記録しています。Swiftログ末尾の「0 tests」はSwift Testing側の表示であり、その前にXCTest 19件を実行しています。

通常のローカル統合検査では、探索結果とモデルの回答を明示したテスト用データに置き換えています。暗号証明、署名、HTTP、契約、ジャーナルは実装を通していますが、The Graph・ENS・公開Sepoliaのライブ検査ではありません。実モデルを使う追加確認は次の節に記録します。

## Push前のローカル実動確認

22時台（JST）に、実際のOllama 0.33.3と既存の `qwen2.5:3b` を使う同じ統合検査も成功しました。モデルのライセンスは非商用の研究・評価範囲を確認し、今回のローカル評価だけに使用しています。

```sh
MATE_TEST_OLLAMA_MODEL=qwen2.5:3b \
MATE_TEST_OLLAMA_URL=http://127.0.0.1:11435 npm run test:local
```

入力「おはようございます。今日の会議は午前10時に始まります。」に対し、実モデルは `Good morning. The meeting is scheduled to begin at 10 AM today.` と応答しました。実証明の検証、HTTP経由の専門サービス呼び出し、契約による支払い確認、結果受領、API再起動後の復元まで成功しています。テスト全体は約21秒でした。決済はAnvil上のシミュレーション、探索はテスト用データです。

最初のGPU実行とCPUライブラリ指定のみの実行は、Metalのcommand queue初期化失敗で停止しました。同梱llama-serverのCPU専用設定を使った後は `library=cpu` とGPUへ0層の割当てを確認し、検査が成功しました。[再現手順](setup.md#実モデルを使うローカル動作確認)を用意しています。ログは `.build/validation/local-ollama-cpu-only-evaluation.log` と `.build/validation/ollama-cpu-only-server.log` です。

APIの起動関数も実際に起動し、healthの未設定表示、認証なしの401、設定不足の503、正常停止時のロック解除を確認しました。Simulatorは再試行してもCoreSimulatorServiceへの接続で停止したため、iOS画面操作の成功とは報告していません。

この制限された実行環境ではSwiftPMの二重sandboxとユーザーキャッシュに制約があるため、iOSビルドには次の環境変数を付けました。外側のファイルシステム・プロセス制限を変更するものではありません。

```sh
CFFIXED_USER_HOME="$PWD/.build/xcode-user" MATE_NESTED_SANDBOX=1 make build-ios
CFFIXED_USER_HOME="$PWD/.build/xcode-user" MATE_NESTED_SANDBOX=1 make build-device
```

## 実行できなかった検査

`make test-ios` は実際に試しましたが、`xcrun simctl list devices available --json` が終了コード1で停止しました。CoreSimulatorServiceへの接続が拒否されるため、この環境でUI・Keychain・iOSネイティブ証明の実行結果は得られていません。SDKビルドの成功をこれらの代用にはしていません。

`make proofs` の回路準備は、上流ProveKitが固定の `~/nargo` キャッシュに書き込む箇所で停止しました。代わりに、このリポジトリの既存CIから取得した準備ファイルを使用しました。回路とNargo.tomlが現在の公開ソースと同じことをGit blobハッシュで照合したうえで、新しい正常証明・6種類の拒否検査・API検査・ローカル統合検査を実行しています。回路をここで新規コンパイルできたとは報告していません。

iOSのネイティブライブラリも、このリポジトリの公開ソースからビルドされたCI成果物を使用し、アーカイブと両ターゲットのライブラリハッシュを照合しました。取得元、ソースの固定リビジョン、SHA-256は [SOURCES](SOURCES.md#local-cryptographic-artifact-provenance) に記録しています。更新したCIは現在のソースをビルドしますが、今回の変更に対するリモートCIの実行・成功は未確認です。

## 外部接続と実機

`npm run configure` で、ローカル認証・ジャーナル暗号化用の乱数だけを含む非公開 `.env` を作成しました。署名鍵やテスト資金は生成していません。APIを実際に起動し、公開healthが `ready:false`、認証済みのaccount操作がHTTP 503 `configuration_required` を返すことを確認しました。検査後はAPIを停止しました。

`./mate --readiness` の現在の結果は `not-release-verified` です。Privy、Sepoliaの契約・署名鍵、ENSv2の管理先、The Graph、実モデルを使う専門サービスは未設定です。ライブ実行を完了するには [セットアップ](setup.md) に従った専用設定が必要です。

実機で残る確認は、カメラ・マイクの明示開始、起動中の停止、背景移行・割込み・脱着後の停止、DockKit追尾、端末内会話、実際の証明生成時間とメモリ使用量です。詳細は [実機・ライブ確認表](device-checklist.md) に未確認として残しています。

## ローカル成果物

- Simulator SDKアプリ: `DerivedData/Build/Products/Debug-iphonesimulator/ZeroKeyMate.app`
- iPhone SDKアプリ: `DerivedDataDevice/Build/Products/Debug-iphoneos/ZeroKeyMate.app`
- Rust検証器: `services/verifier/target/release/mate-verify`
- 検査ログ・結果とSHA-256: `.build/validation/`
- 正常証明・不正条件の拒否ログ: `.build/proofs/`

成果物・ログ・ローカル設定はGitの無視対象です。アプリに含まれるペアリングトークンはこのインストール専用なので、そのまま一般配布する対象にはしません。
