# 検証記録 — 2026-09-07更新

APIと専門サービスの欠けていた実装、iOSの復元・停止操作、起動手順を補完しました。ローカルでの自動検査とiOS SDKビルドは成功しています。実機DockKitと外部サービスのライブ接続は未確認のため、製品全体の受け入れ完了とは扱いません。

最初の検査対象は `8d8b271` を基点とする作業ディレクトリの変更です。実装は `addcbb1`、アクセシビリティ修正は `cdfb6d0` と `5bbe0f6` で [PR #12](https://github.com/susumutomita/ZeroKeyMate/pull/12) にPushしました。環境はApple Silicon、macOS 26.6.2、Xcode 26.6（17F113）、Node.js 24.14.1です。既存のApache-2.0 LICENSEと、別作業のschedulerファイルは変更していません。

## Latest verified status (English)

The implementation at [`5bbe0f6`](https://github.com/susumutomita/ZeroKeyMate/commit/5bbe0f6) passed [CI](https://github.com/susumutomita/ZeroKeyMate/actions/runs/34072016837) and [cryptographic acceptance](https://github.com/susumutomita/ZeroKeyMate/actions/runs/34072016883). CI ran `make test`, Simulator/device SDK builds, `make test-ios`, contract tests and the proof checks. Local `make test SWIFT_TEST_FLAGS=--disable-sandbox` and `make build-ios` also passed after the control fix.

The downloaded XCTest bundle confirms **5 passed, 0 failed, 2 skipped** on iPhone 17 Pro / iOS Simulator 26.2. All three UI tests passed, including actual taps in the icon padding and the portrait accessibility audit. The other passes cover Keychain and private-policy exclusion from the signing document. Native proving and scheme loading are the two explicit skips. [Screenshots and bundle provenance](assets/README.md).

The earlier local acceptance covered 57 automated tests, real proofs, actual HTTP/contract execution and restart/retry recovery. An additional evaluation used a real installed Ollama model. Payments were simulated on Anvil; discovery used explicit fixtures. Physical DockKit, on-device proof performance and live Privy/ENS/The Graph/public-Sepolia acceptance are still unverified. Baseline iOS CI is source-only and skips native proof runtime tests. Local Simulator access was blocked, so CI UI evidence is identified separately.

## Remaining product implementation

The existing [parent issue #4](https://github.com/susumutomita/ZeroKeyMate/issues/4) defines a wider product than the local execution demonstration. Its child issues #5–#11 are still open as of 2026-09-07. Passing the current tests does not close those requirements. The following gaps were also checked against current source, rather than inferred only from open issue status:

| Requirement | Current implementation and remaining work |
| --- | --- |
| [#5 source completion](https://github.com/susumutomita/ZeroKeyMate/issues/5) | Missing API entry points/naming/lock and the Rust lockfile were implemented in this branch. Fidelity to the referenced 94-file archive and every PR #3 integration criterion has not been established; no byte-identical archive recovery is claimed. |
| [#6 operation cancellation](https://github.com/susumutomita/ZeroKeyMate/issues/6) | Signed retry, receipt recovery and persistent server cancellation exist. Discovery/proving/signing do not yet share a request generation across every stop/resume boundary. The current `findProviders` does not bind its result to a draft ID, and `execute` still derives the service from the selected provider. This remains implementation work. |
| [#7 full-stack launch](https://github.com/susumutomita/ZeroKeyMate/issues/7) | `mate` builds/launches the app. API and specialist use separate npm commands. Automatic service orchestration, ownership-aware reuse/stop and an integrated device HTTPS path are not implemented. |
| [#8 runtime pairing](https://github.com/susumutomita/ZeroKeyMate/issues/8) | Configuration is generated into the app bundle; connection changes require rebuilding. In-app pairing and resumable onboarding are not implemented. |
| [#9 conversational actions](https://github.com/susumutomita/ZeroKeyMate/issues/9) | Translation/summary proposals exist. Conversation-to-rules, ENS naming, spend queries and revocation routing remain open. |
| [#10 continuous voice](https://github.com/susumutomita/ZeroKeyMate/issues/10) | Opt-in reply/listen continuation and several stop paths are implemented. The complete session/interruption/approval criteria and physical behavior are not accepted. |
| [#11 expression and stand motion](https://github.com/susumutomita/ZeroKeyMate/issues/11) | Eyes reflect rest/listening/thinking and face position; DockKit exposes tracking control. A shared approval/execution expression model and bounded nod/shake motion coordinator are not implemented. |

Relevant source: [`mate`](../mate), [`CompanionModel.swift`](../apps/ios/ZeroKeyMate/CompanionModel.swift), [`AppConfiguration.swift`](../apps/ios/ZeroKeyMate/AppConfiguration.swift), [`ConversationService.swift`](../apps/ios/ZeroKeyMate/ConversationService.swift), [`DockService.swift`](../apps/ios/ZeroKeyMate/DockService.swift), and [`MateView.swift`](../apps/ios/ZeroKeyMate/MateView.swift). The local terminal demo does not exercise these unfinished mobile workflows.

## Two launch modes — 2026-09-07

`make start-device` selects a connected iOS 26+ iPhone and a signing Team, builds/signs, installs and launches the native app. `make start-simulator` uses the existing Simulator path. `make start` offers an interactive choice: `1` for Simulator, `2` for the phone, or `q` to cancel. Multiple devices/Teams require explicit selection. The user-designated public TenkaCloudPassport workflow was consulted for the make entry points; provenance is in [SOURCES](SOURCES.md).

Local `make test SWIFT_TEST_FLAGS=--disable-sandbox` passed **46 tests: Swift 19, Node 22, launcher unit tests 5**. The launcher tests use labeled metadata fixtures to check ambiguous/offline/unpaired/old-OS device rejection and Team selection; they are not installation evidence. `CFFIXED_USER_HOME="$PWD/.build/xcode-user" MATE_NESTED_SANDBOX=1 make build-ios` passed. Shell syntax, `make help`, and dry-run dispatch for both start targets also passed.

The actual signing-Team selector succeeded using this Mac's valid development identity and its matching certificate's subject OU. No private signing key was exported. An actual `make start` attempt then failed while querying CoreDeviceService, **before device build, installation or launch**. Direct `devicectl list devices` also reported that its CoreDeviceService connection was invalidated and timed out. The phone's connection state could not be established from that failure.

Xcode GUI inspection was attempted as well, but the Computer Use tool returned `Computer Use was not approved to use Xcode`. The earlier Simulator GUI denial remains unresolved; no new local Simulator runtime success is claimed. The make entry points and SDK build are verified; installation and launch on the user's physical iPhone remain blocked in this execution environment. Logs: `.build/validation/tests-start.log`, `ios-build-start.log`, and `device-start.log`.

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

iOSのネイティブライブラリも、このリポジトリの公開ソースからビルドされたCI成果物を使用し、アーカイブと両ターゲットのライブラリハッシュを照合しました。取得元、ソースの固定リビジョン、SHA-256は [SOURCES](SOURCES.md#local-cryptographic-artifact-provenance) に記録しています。

## Push後のCIとSimulator確認

`addcbb1` に対する [暗号検査CI](https://github.com/susumutomita/ZeroKeyMate/actions/runs/34037626377) は成功しました。現在の回路ソースを準備する処理もCI上では成功しています。[通常CI](https://github.com/susumutomita/ZeroKeyMate/actions/runs/34037626382) のenforcementも成功し、iOSではSDKビルド後にSimulator上の7件を実行しました。

iPhone 17 Pro / iOS Simulator 26.2で4件成功、1件失敗、2件skipでした。Keychain、署名文書、会話・設定・履歴画面、横向きの操作確認は成功しました。証明ランタイムを含めないCI構成のため、ネイティブ証明の2件は明示的にskipしています。縦画面のアクセシビリティ検査は、上部のブランド名「Mate.」が `Label not human-readable` と判定されて失敗しました。xcresultの要素スクリーンショットで対象を確認し、読み上げ名を「メイト」にする修正を追加しました。

`cdfb6d0` の [再検査](https://github.com/susumutomita/ZeroKeyMate/actions/runs/34040505670) では縦画面・読み上げ名・Restの検査が成功しました。一方、「文字で話す」のタップ後もホーム画面のままで、会話入力が現れない別の失敗が残りました。xcresultの操作座標と画面階層を確認し、アイコンボタンの透明な余白を含む表示枠全体に `contentShape(Rectangle())` を設定しました。会話ボタンの中央に加えて、会話・設定・履歴ボタンの余白でも画面を開ける検査を追加し、シートを閉じてから次の操作まで実際の消失を待つようにしています。

`5bbe0f6` の [CI](https://github.com/susumutomita/ZeroKeyMate/actions/runs/34072016837) はiOS・enforcementとも成功し、`make test-ios` まで通過しました。[暗号検査](https://github.com/susumutomita/ZeroKeyMate/actions/runs/34072016883) も成功しました。ローカルでの同じ修正後の `make test SWIFT_TEST_FLAGS=--disable-sandbox` はSwift 19件・Node 22件が成功、`CFFIXED_USER_HOME="$PWD/.build/xcode-user" MATE_NESTED_SANDBOX=1 make build-ios` も終了コード0でした。ログは `.build/validation/tests-submission.log` と `.build/validation/ios-build-submission.log` です。

ローカルではユーザーから起動の許可を受けて `open`、Simulator本体の直接起動、GUI操作ツールを試しました。`open` はLaunchServicesエラー、本体の直接起動は異常終了、GUI操作ツールは `Computer Use was not approved to use Simulator` を返しました。ローカルSimulatorは起動確認できていません。会話での許可と、操作ツール側のSimulator利用許可は別の状態でした。

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

### Interactive launch selection — 2026-09-07

`make start` now asks for the launch destination before checking build or device services. Invalid input retries; cancellation and end-of-input do not launch anything. Menu parsing was checked for both destinations, invalid-input retry, cancellation and EOF without invoking device commands. `make test SWIFT_TEST_FLAGS=--disable-sandbox` passed (19 Swift, 22 Node, 5 Python tests), and `CFFIXED_USER_HOME="$PWD/.build/xcode-user" MATE_NESTED_SANDBOX=1 make build-ios` passed. These checks do not establish Simulator or physical-device launch; the previously recorded runtime/tool restrictions remain.

### English hackathon interface — 2026-09-07

App-owned UI, accessibility labels, permission descriptions, errors, service titles and launcher output now use English. Speech recognition and synthesis use en-US; on-device-only recognition and explicit permission/start/stop behavior are unchanged. The UI tests now select English and assert English labels. `make test SWIFT_TEST_FLAGS=--disable-sandbox` passed all 46 tests and `CFFIXED_USER_HOME="$PWD/.build/xcode-user" MATE_NESTED_SANDBOX=1 make build-ios` passed. Local runtime UI tests remain unavailable because CoreSimulatorService refuses the connection. Earlier committed screenshots are explicitly marked as the Japanese build until new CI images are available.

Start/stop, DockKit tracking prerequisites and an optional user-created Shortcuts charger automation are documented. The charger automation and physical stand operation have not been exercised on a device. No automation is silently installed, and charging/docking does not authorize camera or microphone capture.

### Fresh local proof for interim reporting — 2026-09-07

Ran `.tools/bin/provekit-cli prove --prover .build/proofs/mate_policy.pkp --input .build/proofs/valid.toml --out .build/proofs/progress-report.np` and then `verify --verifier .build/proofs/mate_policy.pkv --proof .build/proofs/progress-report.np`. Both exited 0. The new proof SHA-256 is `5e6ac2f174e789b7c0515829c1d3abe27c36a0cf37ccc8725fae936949dc8261`. Logs are `.build/validation/progress-prove.log` and `progress-verify.log`. Proof-resource and both-target native-library integrity checks also passed. This generates a fresh proof from the existing prepared scheme on the Mac; it does not claim circuit recompilation or iPhone runtime execution.


## Local ZK entry point — 2026-09-07

- Added an offline screen backed by the production native ProveKit circuit and verifier. It reports real proof bytes, hashes and elapsed prove/verify time, and checks a modified proof with the native verifier. No network or wallet dependency is present in the exercise model.
- Private-input edits, dismissal and backgrounding discard stale evidence. Native work is cooperative at call boundaries, not forcibly interrupted.
- Paid-request approval now expires across background/rest transitions and draft replacement; provider responses from a previous draft are ignored. Payload/provider controls are locked while a payment is running. Already-submitted requests remain recoverable in Activity.
- `make test SWIFT_TEST_FLAGS=--disable-sandbox`: passed (19 Swift, 22 Node, 5 Python).
- `CFFIXED_USER_HOME="$PWD/.build/xcode-user" MATE_NESTED_SANDBOX=1 make build-ios`: passed with the validated native runtime and circuit resources. CoreSimulatorService is unavailable in the managed shell; this does not constitute a simulator launch or physical-device test.
- Added UI acceptance for the local preflight refusal and extended native proof acceptance to cover the exercise verifier. Their execution on iOS remains pending CI/native-device acceptance; source-only CI cannot execute native ProveKit.

- The offline screen now offers explicit `.np` proof export for independent verification. No private witness is included. The export path builds successfully; a real iPhone-to-PC sharing/verification round trip remains unverified.
- `npm run test:proofs`: passed all three real Rust verifier checks (valid proof, altered proof rejected, substituted statement rejected).
- Re-ran `make test SWIFT_TEST_FLAGS=--disable-sandbox` and the native-resource `make build-ios` after adding export: both passed.

- Final native-library simulator and unsigned device SDK builds passed after sharing-lifetime handling. Public proof export files remain in the OS temporary directory while a share extension may be reading them; changing inputs removes the UI reference rather than deleting an in-flight share.
- Readiness inspection still reports missing Privy, execution API, Graph and specialist configuration. This expected non-release result is not integration acceptance.
- On `dc85ddf`, cryptographic CI [34125544860](https://github.com/susumutomita/ZeroKeyMate/actions/runs/34125544860) passed. CI [34125544854](https://github.com/susumutomita/ZeroKeyMate/actions/runs/34125544854) completed contract enforcement and SDK builds; UI acceptance was still running when this note was written.
