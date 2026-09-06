# ZeroKey Mate

**Your companion. Your rules.**

An independent iPhone + DockKit companion for ETHOnline 2026. Conversation, approximate scene observations and private policy inputs remain on the phone. The user reviews a narrowly scoped disclosure before an external specialist receives it. ProveKit generates a real proof of the approved private policy; a separate verifier checks it before issuing a payment attestation.

## Open the native product

From this repository on an Apple Silicon Mac:

```sh
./mate
```

This entry point prepares dependencies, builds the source-pinned native proving runtime and Noir circuit, generates the Xcode project, and installs/opens the actual app in an installed iOS Simulator. It does not populate fictional accounts, fake ENS names, balances, providers or transaction receipts. The local proof-inspection screen is usable without a Privy account or paid-service deployment. Its results are computed from the values you enter, not supplied fixtures.

Prerequisites: Xcode **26.3 or newer**, a compatible installed iOS 26+ iPhone Simulator, accepted Xcode license, and Homebrew. Downloading public dependencies needs internet access. On a physical iPhone, Xcode must support that phone's installed iOS version. Enable Developer Mode, pair/unlock the phone and set `MATE_DEVELOPMENT_TEAM` in `.env` first; then:

```sh
./mate --device auto
```

DockKit motion, local Japanese speech recognition and Apple Intelligence cannot be established by launching Simulator. The app reports unavailable capabilities instead of inventing responses. No camera or microphone starts without an explicit user action.

## Source delivery and verification status

This revision completes the source wiring of the native client, verifier, authenticated execution API, specialist provider, ENS setup and recovery flows. **The final source revision has not been built, run, deployed or end-to-end tested as part of this delivery.** Tests are included as executable acceptance criteria, not as a claim of success. Physical-device behavior, performance and visual acceptance still require actual evidence. No claim of a finalist placement, security audit, production readiness, or authorship by a particular designer is made.

## Included product paths

- SwiftUI face, blink/reduced-motion support, portrait/landscape layouts and Japanese accessibility labels. Off-white/graphite surfaces; no decorative AI gradients or fabricated dashboards.
- AVFoundation camera lifecycle, local Vision classification/face position, real DockKit connection and system tracking. Background/detach/interruption stop capture; return does not grant consent.
- Japanese on-device Speech input, speech output and Foundation Models conversation. Local notes are stored in device-only Keychain. The model has no wallet or arbitrary network tools.
- Real native ProveKit generation/verification and a local inspection screen, including a mutated-proof rejection check. Private policy commitment, exact request binding, cumulative spend and permitted service checks are implemented in Noir.
- Privy owner/agent wallets. Owner authentication before grants/funding, EIP-712 signatures, independent Sepolia network checks, persisted raw signed transactions and same-transaction recovery. Confirmation requires actual chain receipts, not a returned transaction hash alone.
- ENSv2 exact-name resolution on Sepolia, parent/subregistry setup, owner-controlled subnames and per-name Permissioned Resolver deployment. The agent can edit only `avatar`; the owner can revoke/regrant that permission. Recipient/name resolution is verified against chain state.
- Live Agent0/The Graph discovery followed by ENS and real provider-quote checks. Pinned integration configuration is not a substitute for indexing; absent/mismatched providers disappear rather than becoming demo candidates.
- Authenticated API, encrypted SQLite journals, serialized transaction lanes, separate attestor/relayer/ENS keys, bounded inputs and recovery after response loss.
- Actual specialist work using locally hosted Ollama. Only the reviewed text is sent. A result is prepared before payment and released after the provider verifies the payment event.

## Configure the real integrations once

External accounts, Apple signing identity, testnet funds and ownership of an ENS parent cannot be manufactured by a launcher. Keep secrets in `.env`, never in Git:

```sh
./mate configure
```

This generates local installation tokens and separate **testnet-only** relayer/attestor keys without sending transactions. Fill the documented fields in `.env`: Privy App ID/iOS Client ID (email authentication and additional wallets enabled), Graph API key, and the independently owned ENSv2 Sepolia parent/operator. Keep that operator key separate from the generated service keys; do not reuse a production wallet. `./mate doctor` reports missing inputs without displaying secrets.

Fund the relayer/operator with Sepolia ETH, then deploy the actual contracts and attach the owned parent:

```sh
./mate setup
```

For the bundled specialist, configure a receiving address, HTTPS public endpoint and the actual ERC-8004 identity registry indexed by the selected Agent0 subgraph. The provider receiving address must differ from its ENS owner. Run `./mate provider` while publishing `/agent.json` through your HTTPS reverse proxy; run `./mate register-provider` in another terminal. Registration checks the reachable metadata and the emitted on-chain event. The API must be stopped during registration. The provider reads its metadata file dynamically, so a first registration can publish the file without restarting it.

Start the actual API and specialist together:

```sh
./mate services
```

Ollama is started locally when needed; its configured real model is downloaded if absent. There is no canned LLM fallback. Keep that terminal open. The Simulator connects to loopback; a physical iPhone must use the configured **HTTPS** API URL. Reverse-proxy only the intended routes, retain bearer authentication and never expose Ollama directly. Rebuild with `./mate` after changing client configuration.

In the app: connect Privy, create owner/agent wallets, add Sepolia ETH and test USDC to the owner, approve/deposit a public amount, and authorize a separate private limit. ENS avatar transactions also require Sepolia ETH on the agent wallet. Testnet tokens are not real funds. A live indexed provider and a connected backend are required for the paid flow; local proof inspection remains separate and is never written as a payment receipt.

## Reproducible checks (opt-in)

```sh
make check-sources
make test
npm test
node scripts/compile-contracts.mjs --tests
npm run test:contracts
./mate --verify
```

Contract tests use a local EVM and a test token only in the test harness. The production client has no test accounts or successful-result fixtures. `Native and cryptographic acceptance` is a manually triggered GitHub workflow that builds this revision's circuit/runtime and exports actual results and UI screenshots. It does not pull an old workflow's result to manufacture a pass.

## Security boundary

The current EVM vault verifies **an off-chain verifier's attestation**, not the ProveKit proof directly. A compromised attestor can lie about private-policy compliance, but cannot forge the independent required owner/agent signatures. There is no claim of fully trustless settlement, anonymous transfers, verified model quality, or cryptographic proof that a camera saw the real world.

Public: addresses, transfers, cumulative on-chain spend, policy commitments and proof-related metadata. Private on the phone: policy limit/service mask/salt, conversation, sensor observations and local notes. The execution API and selected specialist see the deliberately approved text. Provider output and retry requests are encrypted at rest. The parent ENS owner retains the authority inherent in its parent namespace. Read [SECURITY.md](SECURITY.md) and [the architecture](docs/architecture.md) before use.

## Repository

`apps/ios` — native client. `Sources/MateCore` — deterministic protocol/encoding. `circuits/mandate` — Noir policy statement. `contracts/src` — vault and ENS resolver factory. `services/api` — verification/discovery/execution. `services/provider` — actual specialist. `services/verifier` — independent ProveKit verifier. `scripts` — setup/launch/recovery tooling.

Existing private product code, identity-card/JPKI code and private wallet implementations are excluded. Future owner-signing integrations enter through the approval/verification boundary, not the private-policy circuit. Public-source references and pinned dependency revisions are listed in [docs/SOURCES.md](docs/SOURCES.md). Apache-2.0; upstream dependencies retain their respective licenses.
