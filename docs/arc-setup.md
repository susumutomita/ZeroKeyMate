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

Open **Settings → Configure connection** on the phone. Run `npm run pair` on the Mac, open the private code file, and enter the API URL and one-time pairing code, select Arc, and supply the confirmed vault and public Privy IDs. **Check connection and save** checks the public deployment and RPC chain, exchanges the code and validates the new session before saving to Keychain. Pending executions or grants prevent switching settlement configuration. A phone cannot reach the Mac through `127.0.0.1`; use an HTTPS endpoint reachable from the phone, without exposing an unauthenticated server. Keep the provider and journal secrets off the phone.

### Physical iPhone HTTPS: Tailscale Serve

Use [Tailscale Serve](https://tailscale.com/docs/features/tailscale-serve) for the private phone-to-Mac connection (official documentation checked 2026-09-10). Install/sign in on both devices using the same approved tailnet, with HTTPS enabled. Account, VPN and HTTPS consent remain explicit user setup steps.

After the real API is ready, run `tailscale serve 8787` in a separate terminal. Keep the API bound to localhost. Copy the HTTPS URL printed by Serve into Mate's connection screen; enter the one-time pairing code separately, never in the URL. Tailnet access does not replace API authentication. Confirm `/health` on the phone, then **Check connection and save** to verify authenticated deployment/chain binding.

Ctrl+C stops this foreground proxy. Do not use Funnel or disable certificate validation for this private connection. The publicly indexed specialist endpoint is configured separately. Until the phone reaches and validates this endpoint, HTTPS acceptance remains pending under #16/#17.

## 5. Record acceptance

1. In airplane mode, generate and verify a local proof, record real time/size, and verify that a modified proof is rejected.
2. Explicitly export the `.np` file and verify it on another machine with the matching `.pkv`.
3. Connect to the real services, sign in with Privy, prepare separate wallets and fund the vault with test USDC.
4. Approve translation-only rules, discover a real indexed provider, review the exact text and quote, prove and execute.
5. Save the Arc receipt and actual translation. Retry the same request after a connection failure and confirm no second payment.

`make test`, `make build-ios`, and `npm run test:local` do not replace this acceptance. Local integration tests use real cryptography/contracts but explicitly simulated Anvil payments and fixture discovery/model responses. Physical DockKit tracking needs separate hardware acceptance.
