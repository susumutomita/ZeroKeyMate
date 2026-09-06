# セットアップ

## 端末だけで使う

Xcode 26以降をインストールして初回起動を完了し、Node.js 22.16以降の22系または24系を用意します。`npm ci --ignore-scripts && npm run configure`、`make build-ios`、`./mate` で起動します。XcodeGenは固定版2.46.0のSHA-256を照合してローカルに配置します。パッケージ管理ツールの特権インストールはしません。

会話はFoundation Models、音声入力は日本語の端末内Speech認識を使用します。対応していない場合はその理由を表示し、クラウドへ切り替えません。Simulatorではモデル・マイク・カメラを利用できない場合があります。外部の翻訳・要約は設定画面から直接依頼を作成でき、会話モデルによる分類に依存しません。

## 証明

Rustのrustupとビルドツールが必要です。`make native-runtime` は固定されたVerityとProveKitの公開ソースからApple Silicon Simulator・iPhone用ライブラリを作成します。`make proofs` はProveKit CLI 1.0.1でこのリポジトリのNoir回路をコンパイルし、正常な証明と6種類の不正な条件を検査します。

```sh
make native-runtime
make proofs
cargo +nightly-2026-03-04 build --release --locked --manifest-path services/verifier/Cargo.toml
npm run test:proofs
make build-ios
./mate --verify
```

準備ファイルとネイティブライブラリのハッシュをビルド時に検査します。これらのマニフェストは、信頼済みのビルドから配布する必要があります。攻撃者が鍵とマニフェストを両方置き換えられる環境を防ぐ仕組みではありません。

## Sepolia・Privy・ENS・The Graph

`.env.example` の変数を設定します。値をチャットや公開ログへ貼る必要はありません。

- Privy: アプリとiOSクライアントを作成し、メールログインと追加Ethereumウォレットを許可します。アプリのbundle IDとPrivyの設定を一致させます。アプリには公開IDだけを入れます。
- MateVault: `npm run compile:contracts` で契約をコンパイルし、Sepoliaへデプロイします。コンストラクターはCircleのSepolia USDC `0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238` と証明検証者のアドレスです。デプロイやテスト資金の入金は、このリポジトリの起動時には実行しません。
- API: `MATE_VAULT_ADDRESS`、`SEPOLIA_RPC_URL`、それぞれ別の `MATE_ATTESTOR_PRIVATE_KEY` と `MATE_RELAYER_PRIVATE_KEY` を設定します。APIはchain ID、契約、USDCの桁数、検証者を照合します。秘密鍵はiPhoneに組み込みません。
- ENSv2: 所有・管理できる親ドメインとUserRegistryを用意し、`ENS_PARENT_NAME` と `ENS_SUBREGISTRY_ADDRESS` を指定します。`ENS_OPERATOR_PRIVATE_KEY` はそのレジストリの登録権限を持つ別キーです。`MateResolverFactory` をSepoliaへデプロイし、`ENS_RESOLVER_FACTORY` を指定します。APIは公開ルートからの探索結果と設定のレジストリが一致することを確認します。ENSv1への推測によるフォールバックはありません。
- The Graph: `GRAPH_API_KEY` と対応するERC-8004インデックスの `GRAPH_SUBGRAPH_ID` を指定し、実際の応答・スキーマを検証します。`MATE_PROVIDERS_JSON` は登録済みの提供者の許可リストであり、候補を捏造するカタログではありません。

提供者の許可リストは次の形式です。サンプル値を稼働中の提供者として登録しないでください。

```json
[{
  "id": "11155111:実際の登録ID",
  "service": 0,
  "price": "100000",
  "owner": "実際の登録所有者の0xアドレス",
  "recipient": "実際の支払先の0xアドレス",
  "ensName": "実際の提供者名.eth",
  "endpoint": "https://専門サービスのホスト",
  "bearerToken": "32文字以上の個別トークン"
}]
```

service 0は日英翻訳、1は原文の言語での要約です。priceは小数点以下6桁の整数単位です。The Graphで所有者・稼働状態・ENS名・URLを照合し、ENSアドレスと実サービスの料金を再確認します。キーなし・索引エラー・不一致・接続失敗では提供者を利用できません。ライブ接続の成功を確認するまでは統合済みと報告しないでください。

## 専門サービス

Ollamaと、ライセンスを確認したローカルモデルを別途用意します。アプリがモデルの重みを取得したり、モデル提供者に自動登録したりすることはありません。`OLLAMA_MODEL` にインストール済みモデル名を指定します。

`PROVIDER_RECIPIENT`、`PROVIDER_SERVICE`、`PROVIDER_PRICE`、`PROVIDER_API_TOKEN`、`PROVIDER_JOURNAL_KEY`、`MATE_ATTESTOR_ADDRESS` を設定し、`npm run provider` で起動します。専門サービスには送金用の秘密鍵が不要です。Ollamaへの接続先は `OLLAMA_URL` です。HTTPは同一ホストのループバックだけを許可します。

iPhoneから接続するときは、認証トークンを維持するHTTPSのリバースプロキシをAPIと専門サービスに用意してください。HTTPのLANアドレスは使用できません。APIも専門サービスも、既定では127.0.0.1だけで待ち受けます。設定後にアプリを再ビルドします。構成ファイルに組み込まれるペアリングトークンを含むビルドは、不特定多数に配布しないでください。

### 実モデルを使うローカル動作確認

`npm run test:local` は実証明・HTTP・Anvilの契約を使用します。通常は探索結果とモデル応答を明示したテスト用データに置き換えます。ライセンスを確認済みのインストール済みOllamaモデルを指定すると、モデル応答を実際に生成し、支払い後の結果取得とAPI再起動後の復元を検査できます。

```sh
MATE_TEST_OLLAMA_MODEL=インストール済みモデル名 \
MATE_TEST_OLLAMA_URL=http://127.0.0.1:11434 npm run test:local
```

Anvil、コンパイル済み契約、ProveKit CLI・準備ファイル・Rust検証器が必要です。モデルは取得しません。探索はテスト用データのままであり、決済もローカルシミュレーションです。実モデルが利用できなければ検査は失敗します。

このMacのOllama 0.33.3では、CPU用ライブラリ指定だけではMetal初期化を避けられませんでした。同梱llama-serverの公開された設定に従い、検査用サーバーを次のように起動するとCPUだけで動作しました。既存サーバーとポートを分け、検査後はCtrl-Cで停止します。

```sh
OLLAMA_HOST=127.0.0.1:11435 OLLAMA_NO_CLOUD=1 OLLAMA_NOPRUNE=1 \
OLLAMA_CONTEXT_LENGTH=2048 OLLAMA_MAX_LOADED_MODELS=1 OLLAMA_NUM_PARALLEL=1 \
OLLAMA_KEEP_ALIVE=30s LLAMA_ARG_DEVICE=none LLAMA_ARG_FIT=off \
LLAMA_ARG_N_GPU_LAYERS=0 ollama serve
```

この場合はテスト側のURLも `http://127.0.0.1:11435` にします。設定の出典と今回評価したモデルの利用範囲は [SOURCES](SOURCES.md) に記録しています。

## 復元・停止

APIと専門サービスはそれぞれ暗号化SQLiteジャーナルと単一プロセスロックを使います。SIGINT/SIGTERMは処理終了後にロックを解放します。強制終了した場合は、プロセスが停止していることを確認して `npm run unlock -- api` または `npm run unlock -- provider` を実行します。生存中のPIDのロックは解除できません。

ジャーナルと暗号鍵は対応する組で保存してください。処理結果が不明な間に削除・再生成すると、安全な再送ができません。古い取引が未確定の場合、新しいnonceを割り当てず同じ署名済みバイト列を再送します。サーバーを再起動した後、アプリの履歴から結果を照会してください。決済はエスクローではなく、支払後の専門サービス停止に対する自動返金はありません。

## 制限されたビルド環境

書き込み先が作業ディレクトリに限られる場合、キャッシュをその中へ置きます。`make test SWIFT_TEST_FLAGS=--disable-sandbox` は外側の実行制限を維持したままSwiftPMの二重sandboxを避けます。Xcodeでも必要な場合だけ次を使用できます。

```sh
CFFIXED_USER_HOME="$PWD/.build/xcode-user" MATE_NESTED_SANDBOX=1 make build-ios
```

これはSimulatorサービスへの権限を追加しません。またProveKit CLIの回路準備は上流の固定された `~/nargo` キャッシュに書き込むため、その場所が許可されない環境では停止します。そこで回路を準備済みと偽装せず、通常のホストまたはCIで生成した信頼済みの準備ファイルを別途使用し、出典を記録します。
