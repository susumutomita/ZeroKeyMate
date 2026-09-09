# Arc and the live specialist flow

This guide configures real testnet services. It is separate from the offline **Try private rules on this device** exercise, which needs no account. The Arc adapter and local chain acceptance are implemented; Circle login, live Privy/Graph acceptance, a public vault and the complete physical-iPhone flow remain unverified.

## 1. Prepare the build

```sh
npm ci --ignore-scripts
make configure
make proofs
make native-runtime
cargo +nightly-2026-03-04 build --release --locked --manifest-path services/verifier/Cargo.toml
make circle-setup
```

The native build is required for actual on-device proof generation. Source-only builds show that proving is unavailable. `configure` preserves existing `.env` files: migrate an older Sepolia configuration deliberately using `.env.example`. Never paste private keys or pairing tokens into a submission or chat.

Arc Testnet uses chain **5042002**, RPC `https://rpc.testnet.arc.network`, and USDC ERC-20 address `0x3600000000000000000000000000000000000000`. Mate uses the ERC-20 interface's **6 decimal units**, not the native gas balance's 18 decimals. A price of `100000` means 0.10 test USDC. See [Arc connection information](https://docs.arc.io/integrate/connect-to-arc) and [USDC semantics](https://docs.arc.io/arc/concepts/stablecoin-native-model).

## 2. Configure the attestor and vault

The Circle Agent Wallet signs only an EIP-712 `ProofApproval` binding the action hash and verified proof hash to this chain, vault and protocol version. It receives neither the private budget nor the policy witness. The relayer is a separate wallet that broadcasts transactions. The vault trusts this off-chain attestor; Circle does not turn it into an on-chain ProveKit verifier.

Review Circle's terms and complete its interactive testnet login yourself:

```sh
make circle-login EMAIL=you@example.com
```

This sends an authentication email when authorized by the operator. CLI terms acceptance and login are not automated by app installation. Use the same `CIRCLE_CLI_HOME` (default `.data/circle`) for login and the API. The optional CLI is pinned to 1.0.0; telemetry is disabled for Mate invocations. Follow the official [Agent Wallet quickstart](https://developers.circle.com/agent-stack/agent-wallets/quickstart) to provision/list an **agent** wallet on `ARC-TESTNET`. A local CLI wallet does not qualify.

Set these in the ignored `.env`:

- `MATE_CHAIN_ID=5042002`, `MATE_RPC_URL=https://rpc.testnet.arc.network`
- `MATE_ATTESTOR_MODE=circle`, `CIRCLE_ATTESTOR_ADDRESS=<agent wallet address>`
- `MATE_ATTESTOR_PRIVATE_KEY=` (empty in Circle mode)
- `MATE_RELAYER_PRIVATE_KEY=<separate testnet relayer key>`
- `MATE_ATTESTOR_ADDRESS=<same Circle attestor address>` for the independent specialist

Fund the relayer with Arc testnet USDC for gas using the official [Circle faucet](https://faucet.circle.com/). Then deploy:

```sh
make deploy-vault
```

The command validates the RPC chain and token, journals the signed deployment transaction before broadcasting, confirms the receipt and contract configuration, and writes public evidence to `.build/deployments/5042002.json`. Set `MATE_VAULT_ADDRESS` to that confirmed address. Retrying uses the existing deployment journal; do not delete the journal to recover a timeout. Constructor/bytecode changes require a deliberately managed new deployment.

Local-key attestation remains available with `MATE_ATTESTOR_MODE=local` for independent testing. It is not a Circle Agent Stack demonstration.

## 3. Configure real discovery and the specialist

Set `PRIVY_APP_ID` and `PRIVY_IOS_CLIENT_ID` from your Privy app, enable email login and embedded Ethereum wallets, and authorize the app's actual iOS bundle identifier. The app uses distinct owner and agent wallets. Changing Privy IDs after the SDK has initialized requires closing and restarting the app; connection/network changes with the same IDs reuse its singleton safely.

Set `GRAPH_API_KEY` and the matching `GRAPH_SUBGRAPH_ID`. Provider registration identity is currently indexed on **Sepolia**, while settlement is **Arc**. `MATE_PROVIDERS_JSON` pins the expected indexed owner, agent wallet recipient, HTTPS endpoint, service and price. A provider appears only if a live Graph response matches those pins and its live quote matches the actual chain, vault and token. No ENS lookup is claimed on this path.

Example shape (replace all placeholders; these are not working records):

```json
[{"id":"11155111:REGISTRATION_ID","service":0,"price":"100000","owner":"0xREGISTERED_OWNER","recipient":"0xREGISTERED_AGENT_WALLET","endpoint":"https://YOUR_SPECIALIST","bearerToken":"YOUR_PROVIDER_TOKEN"}]
```

Configure `PROVIDER_API_TOKEN`, `PROVIDER_JOURNAL_KEY` (64 hex characters), `PROVIDER_RECIPIENT`, `PROVIDER_SERVICE` (`0` translation / `1` summary), `PROVIDER_PRICE`, and `OLLAMA_MODEL`. Install a model only after reviewing its license; the app does not download one. The provider must have the same chain, vault, token and attestor as the API. Expose its authenticated endpoint through your own HTTPS service and register that exact endpoint in the indexed record. The Graph record and live query must exist; configuration alone creates neither.

## 4. Start, pair and stop

```sh
make dev             # start the actual API + specialist, then choose Simulator/iPhone
make dev-simulator
make dev-device
# Or, when the app is already installed:
make services
```

These foreground commands fail if the real dependencies are unavailable. Ctrl+C stops the servers they own, retaining recovery journals. The iOS app remains installed/running; use **Rest** to stop capture and voice, or close it with the app switcher. `make start`, `make start-simulator`, and `make start-device` launch just the app and remain usable without live-service credentials.

Open **Settings → Configure connection** on the phone. Enter the API URL and pairing token, select Arc, and supply the confirmed vault and public Privy IDs. **Check connection and save** checks the authenticated API's deployment and RPC chain before saving to Keychain. Pending executions or grants prevent switching settlement configuration. A phone cannot reach the Mac through `127.0.0.1`; use an HTTPS endpoint reachable from the phone, without exposing an unauthenticated server. Keep the provider and journal secrets off the phone.

### One fixed HTTPS path for a physical iPhone: a local reverse proxy with a locally-trusted certificate

This is the one supported method; it keeps the API on the same Wi-Fi network, issues a certificate the iPhone is asked to trust explicitly, and never disables TLS verification on either side.

1. Install [mkcert](https://github.com/FiloSottile/mkcert) and Caddy (`brew install mkcert caddy`), then create a local CA and a certificate for your Mac's LAN hostname or IP (find it with `ipconfig getifaddr en0`):
   ```sh
   mkcert -install
   mkcert 192.168.1.50 mate.local   # replace with your Mac's actual LAN IP/hostname
   ```
2. Run a minimal reverse proxy in front of the API port (`8787` by default) using the certificate mkcert just generated:
   ```sh
   caddy reverse-proxy --from 192.168.1.50:8787 --to 127.0.0.1:8787 --tls "192.168.1.50+1.pem" "192.168.1.50+1-key.pem"
   ```
3. AirDrop `$(mkcert -CAROOT)/rootCA.pem` to the iPhone, install the profile in **Settings → General → VPN & Device Management**, then enable full trust for it in **Settings → General → About → Certificate Trust Settings**. This trusts only your own locally-generated CA, not a public one; nothing else on the internet is trusted by it.
4. In **Configure connection**, set the API URL to `https://192.168.1.50:8787` (the address from step 1/2) and the pairing token from `.env`. The phone must be on the same Wi-Fi network as the Mac.

Stop the proxy with Ctrl+C when you are done; it is a separate process from `make dev`/`make services` and is not started or stopped automatically by them. Do not reuse this certificate or CA outside local development, and do not commit `rootCA-key.pem` or the generated `*-key.pem` files anywhere.

## 5. Record acceptance

1. In airplane mode, generate and verify a local proof, record real time/size, and verify that a modified proof is rejected.
2. Explicitly export the `.np` file and verify it on another machine with the matching `.pkv`.
3. Connect to the real services, sign in with Privy, prepare separate wallets and fund the vault with test USDC.
4. Approve translation-only rules, discover a real indexed provider, review the exact text and quote, prove and execute.
5. Save the Arc receipt and actual translation. Retry the same request after a connection failure and confirm no second payment.

`make test`, `make build-ios`, and `npm run test:local` do not replace this acceptance. Local integration tests use real cryptography/contracts but explicitly simulated Anvil payments and fixture discovery/model responses. Physical DockKit tracking needs separate hardware acceptance.
