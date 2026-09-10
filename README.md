# ZeroKey Mate

**Your companion. Your rules.**

A private iPhone companion that proves each paid AI request follows your rules.

Mate is designed to keep everyday conversation on your iPhone. When you ask a specialist to translate or summarize something, you review the exact text, provider, recipient and price first. A ProveKit proof checks the request against your private spending policy; a narrowly scoped Ethereum vault enforces the signed execution. The language model has no authority to approve a payment.

[Companion experience](docs/design/companion-experience.md) · [日本語](docs/README.ja.md) · [Demo guide](docs/demo.md) · [Submission copy](docs/submission.md) · [Delivery schedule](docs/schedule.md) · [Arc setup](docs/arc-setup.md) · [Prize strategy](docs/prize-strategy.md) · [Interim report](docs/interim-report.md) · [Architecture](docs/architecture.md) · [Validation](docs/validation.md)

<p align="center">
  <img src="docs/assets/face-home.png" width="260" alt="Mate home showing only two eyes, without visible text or a toolbar.">
  <img src="docs/assets/face-rest.png" width="260" alt="Mate resting after the Rest control is pressed, with the camera stopped.">
</p>

The home screen is Mate’s face: no visible text or toolbar. Tap the face to open controls; touch and hold to rest.

<p align="center"><em>Actual iOS Simulator captures: home → Rest. These screens do not demonstrate live conversation, DockKit tracking or a payment. <a href="docs/assets/README.md">Capture provenance</a>.</em></p>

## Start with local ZK

Swipe up on Mate’s face, open **Settings**, then choose **Try private rules on this device**. Enter a private spending limit and a public translation price, then tap **Generate and verify proof**. The app runs the production ProveKit circuit and verifier locally and reports the actual prove-plus-verify time, proof size and commitments. It also modifies a copy of the proof and checks that the native verifier rejects it. No wallet or API configuration is required for this exercise; the native runtime and circuit resources must be bundled at build time.

After installation, try it in airplane mode. Change the limit or permission and the previous evidence is cleared. A request outside the rules is rejected at preflight and labeled **No proof generated**; this is distinct from cryptographic rejection of a modified proof. Closing the screen or backgrounding discards its result, although an in-progress native call must finish before resources can be released.

After a successful run, tap **Prepare proof file for sharing**, then **Share proof file** to transfer the actual `.np` file to another computer. Sharing is explicit. Verify it with the matching circuit key from this build:

```sh
.tools/bin/provekit-cli verify --verifier .build/proofs/mate_policy.pkv --proof /path/to/exported-proof.np
```

The verifier key must match the bundled setup manifest; using another circuit or setup is not a valid comparison. The proof file contains embedded public inputs, not the private witness. This phone-export round trip still needs physical-device acceptance.

This is an **offline proof exercise**, using fresh request identifiers and example Sepolia addresses, with no payment or wallet signature. The paid execution flow separately binds the actual transaction context. Physical-iPhone measurements and the new screen's runtime acceptance remain pending; a simulator build is not device evidence.

The private budget, allowed-service mask and salt are not sent to a verifier. Public spending and successful requests can still reveal information such as a lower bound on the budget. The current vault trusts the server's signed proof-verification attestation; it does not verify ProveKit directly on-chain.

## Who is Mate for?

Mate is a desk companion for people who want help from AI specialists while keeping control of what they share and spend. Everyday conversation is designed to stay on the iPhone. A paid external task begins with a specific review: this text, this provider, this recipient and this price.

For example: **“Translate this Japanese meeting note into English. Allow translation only, with a total limit of 5 test USDC until tonight.”** The owner sets those terms in **Your rules**, reviews the proposed text and quote, and approves the request. The intended mobile flow proves compliance on the iPhone, verifies the proof, pays the specialist and returns the translation. Conversational rule setup and the complete mobile flow still need acceptance; the local protocol demo is the verified part today.

## Use cases

| Situation | What the user does | What Mate is intended to provide |
| --- | --- | --- |
| Share a meeting note with an overseas teammate | Select only the Japanese text to translate, allow translation and set a spending limit | An English translation without disclosing the rest of the conversation or the private spending policy |
| Get a shorter version of a long note | Request a summary and review the exact excerpt and quote | A summary of the approved text; no unrelated notes or camera frames attached |
| Recover after a connection failure | Check the pending request in **Activity** | Recover the same request and receipt without a second payment; demonstrated in the local integration test |

These are use cases for the prototype, not claims that all three have been validated on an iPhone. Current specialist tasks are translation and summarization. Purchases, unrestricted web browsing and general autonomous wallet control are outside this demo.

## Why a stand, on-device AI and client-side ZK?

| Part | Purpose |
| --- | --- |
| Compatible Belkin / DockKit stand | Gives the desk companion a physical presence and can support system tracking while the camera is explicitly active. Hardware acceptance remains open. |
| On-device AI | Handles ordinary conversation locally on supported devices. |
| Client-side ProveKit proof | Proves that the concrete paid request complies with a committed private policy, without publishing its budget, allowed-service mask or salt. Target-iPhone performance remains unverified. |
| Ethereum vault | Checks signed authority, the concrete action, expiry, revocation and replay; transfers test USDC. It trusts the off-chain proof attestor for private-policy compliance. |

The stand supports the companion experience; it is optional for proving or paying. ZK does not encrypt speech or video, guarantee the quality of a translation, or prove a provider's trustworthiness. The specialist receives the approved text, and payment amounts and recipients are public. The prototype uses test funds only.

## The moment we want to make possible

“Translate this meeting note, but only within the rules I approved.”

1. **Set your rules.** Approve a versioned mandate for a dedicated agent wallet, a budget, allowed services and an expiry.
2. **Choose what leaves the phone.** Review the text and a specialist's current quote. The conversation history is not attached.
3. **Prove and execute.** Prove that this specific request fits the committed policy. Verify the proof, owner grant and agent signature before transferring test USDC.
4. **Get the result, even after a disconnect.** Recover the same signed request and receipt. Retrying a completed request cannot spend again.

The local acceptance test exercises steps 3–4 with a real proof, HTTP services and Solidity contracts. The complete iPhone-to-public-Arc flow still needs live acceptance.

## Why Ethereum and zero knowledge?

An assistant's instructions are not a spending boundary. MateVault checks authority, expiry, revocation, spend state and replay on chain. Each action binds the chain, vault, mandate, concrete recipient, amount, service, disclosed text hash and nonce. The vault supports one configured token and a fixed transfer operation.

The proof keeps the policy's budget, allowed-service mask and salt out of the public grant. The payment amount and recipient remain public; the specialist receives the text you approve. Live Graph records select candidates; each quote separately binds the Arc settlement deployment. Registry identity does not authorize spending.

**Trust boundary:** ProveKit verification runs off chain. MateVault trusts the configured attestor's signature on its result. A compromised attestor can approve a policy violation; collusion with the agent can spend beyond the private budget. This is not an on-chain ZK verifier. See the [full trust assumptions](docs/architecture.md#trust-assumptions).

## What works today

| Component | Evidence | Remaining acceptance |
| --- | --- | --- |
| Native SwiftUI app | iOS Simulator/device SDK builds; CI exercises real screens, Keychain and persistent English/Japanese switching | Physical iPhone, camera, microphone, Foundation Models and DockKit |
| ProveKit + Noir policy circuit | Real native Simulator proof independently verified on Mac; modified-proof rejection, six invalid-witness rejections and API tamper tests | Proof generation latency and memory on the target iPhone |
| MateVault | 12 contract tests on Anvil, including replay and authorization failures | Public Arc deployment and live receipts |
| API + specialist + recovery | Real proof → HTTP → vault → result, including API restart and retry without duplicate spend | Complete mobile/live-service flow |
| Local specialist model | Actual Ollama translation and recovery checked locally | A separately configured, license-reviewed deployment |
| Privy | Pinned iOS SDK and signing adapter compile | Live login and owner/agent signing |
| Arc + Circle Agent Stack | Arc chain/token binding and an allowlisted Circle Agent Wallet attestation adapter; both supported chain domains pass local acceptance | Actual Circle session, public vault and testnet receipts |
| The Graph | Live indexed owner, agent wallet and endpoint validation; quote binds the settlement chain/vault/token | Live provider registration and query evidence |

**Current scope: a working local prototype, with further app implementation and hardware/live acceptance still open.** The [product backlog](https://github.com/susumutomita/ZeroKeyMate/issues/4) tracks remaining acceptance, broader conversation actions and expressive stand motion. A foreground full-stack launcher, validated runtime pairing, and cancellation checks before signing are implemented. Basic continuous voice is implemented, but its full acceptance criteria are not closed. [Implementation status](docs/validation.md#remaining-product-implementation).

Anvil payments are simulations. Default local discovery and model responses are labeled fixtures; the optional Ollama mode generates a real response. No unavailable integration is replaced by a success screen. [Detailed results](docs/validation.md).

## Run the app

Use an Apple Silicon Mac, Xcode 26 or later with an iOS Simulator runtime, and Node.js 22.16+ on the 22.x line or Node.js 24.x. Open Xcode once to finish its setup. The scripts install a checksum-pinned XcodeGen inside this project.

The current review build is in [PR #12](https://github.com/susumutomita/ZeroKeyMate/pull/12). Until it is merged, check out its branch:

```sh
git clone --branch codex/complete-local-runtime https://github.com/susumutomita/ZeroKeyMate.git
cd ZeroKeyMate
npm ci --ignore-scripts
npm run configure
make test
```

Choose where to launch (enter `1` for Simulator, `2` for a connected iPhone, or `q` to cancel):

```sh
make start
```

To launch directly without the menu:

```sh
make start-simulator  # iPhone Simulator
make start-device     # Connected iPhone: build, sign, install and launch
```

For the physical phone, connect it over USB, unlock it, trust this Mac and enable Developer Mode. The launcher selects a single connected, paired iPhone running iOS 26+ and a single signing Team from the Mac's valid Apple Development identities. If there is more than one, specify `MATE_DEVICE_UDID=UDID make start` and/or `MATE_DEVELOPMENT_TEAM=TEAM_ID make start`. `make help` lists both modes. It never silently switches from a phone to a Simulator.

`configure` creates an ignored `.env` containing server journal/provider keys and preserves an existing file. It does not create wallets, fund an account or deploy contracts. A fresh clone can open the UI without payment credentials. Source-only builds explicitly disable proving and paid execution until the real runtime and circuit are built.

The app defaults to English. This companion update starts in English once even when an earlier development build saved Japanese; subsequent selections persist. **Settings → Language** selects the interface language. **Spoken language** selects the initial recognition language (Japanese by default). Each transcribed or typed message selects its own English/Japanese reply and read-aloud voice. Recognition then follows that language; this is not simultaneous bilingual speech recognition. iOS consent dialogs follow the device's app-language setting. The home screen has only the eyes: tap the resting face to wake Mate, say **おやすみ** to stop camera and microphone, and touch and hold or swipe up for controls/settings. Tapping an awake face does not open settings. **Enable voice wake** explicitly starts on-device Japanese recognition while foregrounded: **こんにちは** starts the camera and conversation; other standby speech is discarded. Rest, backgrounding, interruptions and undocking disarm it. After goodnight, tap to wake again or explicitly enable voice wake. Camera and DockKit setup do not depend on model availability. No model-unavailable cloud fallback is used.

If a signing identity is missing, run `make project`, open `apps/ios/ZeroKeyMate.xcodeproj`, and configure your Apple Account/Signing Team in Xcode before retrying. DockKit requires compatible physical hardware. These make targets launch the native app. For the configured API and specialist together, use `make dev` (chooser), `make dev-simulator`, or `make dev-device`; Ctrl+C stops accepting requests and waits for admitted work before releasing the journals. Client connections are closed after five seconds, but this does not cancel a submitted transaction or release its journal early. A slow external request can therefore delay shutdown. Running `make dev*` or `make services` again while an earlier invocation's services are still alive reuses them instead of starting a second copy on the same ports; it never stops an unrelated process holding those ports. **Settings → Configure connection** validates and saves the phone connection. Follow [Arc and live-service setup](docs/arc-setup.md); required accounts and test funds are not created automatically.

## Reproduce the proof and payment demo

Install Rust/rustup and Foundry with `anvil` available on PATH. Dependency versions, public sources and licenses are recorded in [SOURCES](docs/SOURCES.md). No model is downloaded automatically.

```sh
make test-contracts
make proofs
cargo +nightly-2026-03-04 build --release --locked --manifest-path services/verifier/Cargo.toml
npm run test:proofs
npm run test:local
```

This generates an actual proof and exercises the execution/recovery protocol on a disposable Anvil chain. It uses published test accounts and a test token; it is **local payment simulation**, not a public Arc or Sepolia payment. The acceptance script exercises both supported chain domains. See the [demo guide](docs/demo.md) for the real-model option, rejection checks and a three-minute walkthrough.

To include ProveKit in the iOS app and run native acceptance on a usable Simulator:

```sh
make native-runtime
make build-ios
./mate --verify
```

Normal setup builds from pinned public sources, without relying on expiring CI artifacts. Host restrictions that prevent circuit preparation or Simulator access must be resolved before those checks can run; an SDK build is not a runtime test.

## How it fits together

```mermaid
flowchart LR
    U[User reviews text and price] --> I[iPhone: policy and agent signature]
    I --> P[ProveKit policy proof]
    I --> A[Execution API]
    P --> V[Rust proof verifier]
    A --> V
    A --> D[The Graph candidates + bound quote]
    V --> T[Off-chain attestor]
    T --> C[MateVault: grant, action, replay, test USDC]
    A --> S[Specialist: prepare approved text]
    C --> R[Canonical payment receipt]
    R --> S
    S --> I
```

The Graph path requires live configuration; local acceptance substitutes explicitly labeled discovery fixtures. The specialist independently checks the payment event before releasing its result. Settlement is not escrow: provider failure after payment has no automatic refund.

| Code | Responsibility |
| --- | --- |
| [`apps/ios`](apps/ios) | Companion UI, sensor consent, local conversation, signing and recovery |
| [`Sources/MateCore`](Sources/MateCore) | Versioned policy/action encoding and receipt validation |
| [`circuits`](circuits) | Private-policy compliance circuit |
| [`services/api`](services/api) | Discovery, proof verification, execution and encrypted journal |
| [`services/provider`](services/provider) | Ollama specialist, encrypted prepared result, independent payment check |
| [`services/verifier`](services/verifier) | Real ProveKit verification and public-input extraction |
| [`contracts`](contracts) | MateVault and ENS address resolver |

## Consent, sources and submission

Camera and microphone require explicit starts. Docking alone starts no recording, upload or payment. Stop remains effective during startup; backgrounding, interruptions and detach stop capture. Returning foreground or re-docking does not restore consent. Camera OFF is reported only after the service stops. Camera-intent transitions have unit coverage; physical behavior remains on the [device checklist](docs/device-checklist.md).

No audio recordings, camera frames or conversation history are uploaded. Approved specialist text/results are stored in encrypted server journals whose operators hold the keys. ProveKit proves policy compliance; it does not encrypt media or establish real-world identity. Production funds and identity-card support are outside this prototype.

For ETHGlobal review: [submission copy and open fields](docs/submission.md), [demo script](docs/demo.md), and [development history / AI assistance](docs/development-history.md). Event, track, prize eligibility and the final demo video are still to be confirmed. Existing commits are disclosed rather than represented as work from an unconfirmed event window.

Original project code is licensed under [Apache-2.0](LICENSE). Public sources and reviewed dependency licenses are in [SOURCES](docs/SOURCES.md) and [third-party notices](docs/THIRD_PARTY_NOTICES.txt). This provenance record is not a formal clean-room audit.

### Start and stop

Run `make start`, then enter `1` for Simulator or `2` for a connected iPhone. In the app, read the welcome explanation and tap **Spend time together** to explicitly start camera tracking and continuous on-device voice together. Swipe up for **Controls** and choose **Read or type a message** for text conversation. Camera can also be started separately in **Settings → Start camera**. The black pupils move within white oval eyes to follow the detected face in both directions; the controls panel reports whether a face is detected. Settings reports the stand connection, hardware tracking-button state and whether DockKit reports a tracked subject.

Say **おやすみ** while listening, or choose **Rest and stop camera and microphone** in Controls, to stop sensors and pause conversation. **Settings → Stop camera** stops only the camera. Backgrounding the app or detaching a connected DockKit stand stops capture and voice; returning or reattaching does not restart them. Wait for **Camera off** before treating capture as stopped. Rest does not revoke a spending mandate or undo a submitted transaction; revoke mandates in **Your rules** and inspect pending transactions in **Activity**.

A compatible DockKit stand is optional. Mounting the phone alone does not launch Mate or start capture. With Mate open, explicitly start the camera; system tracking is requested only while capture is active, a stand is connected and its tracking button is enabled. Physical stand connection and tracking remain unverified.

The launcher exits after opening the app: Ctrl+C after that does not stop Mate. To close it, use the iPhone app switcher or quit Simulator with Command-Q.

During `make dev*` startup, Ctrl+C terminates the app launcher's own process group, including its shell/build children, before releasing launcher ownership. It first requests termination and then force-stops that owned group if necessary. It never loads a PID from a lock file to choose a process to stop. Already-running services reused from another invocation remain owned by that invocation. If shutdown cannot be confirmed, ownership is retained and the launcher reports the failure.

### Open Mate when charging

After installing Mate on your iPhone, create a personal automation in **Shortcuts → Automation → + → Charger → Is Connected**. Choose **Run Immediately** (or disable **Ask Before Running** on versions that use that setting), add the **Open App** action, select **Mate**, and save. Test with the iPhone unlocked by disconnecting and reconnecting power. If iOS asks you to unlock, do so; unattended launch while locked is not verified.

Apple documents the [charger connection trigger](https://support.apple.com/guide/shortcuts/apde31e9638b/ios) and [automatic execution of charger automations](https://support.apple.com/guide/shortcuts/apd602971e63/ios). This trigger is not specific to Belkin: other chargers also activate it. Create and verify the automation on your own phone; the repository does not install it automatically. It opens the app only. Start camera and voice explicitly inside Mate. To stop automatic opening, disable or delete this automation in Shortcuts.

### Merchant app

Run `npm run merchant` to open the English-first shop console at `http://127.0.0.1:8790`. The shop independently verifies the client ZK proof and withholds delivery until its own on-chain payment check succeeds. See [merchant setup and trust boundaries](docs/merchant.md).

### Pair an iPhone without rebuilding

Once the API deployment and proof verifier are ready, run `npm run pair` on the Mac. Open the private `pairing-code.txt` at the path printed by the command and enter its code under **Settings → Configure connection → One-time pairing code**. Enter the reachable HTTPS API origin, matching testnet/vault and public Privy IDs, then check and save. The app checks the public deployment and RPC chain before exchanging the code, checks its new session, and saves only after all checks pass.

A code expires in 10 minutes and works once. Its device session expires after one hour or 500 authenticated requests. Repeat the command and update the same connection to renew without losing pending requests. An environment change is refused while a grant or execution is pending. `npm run pair -- --revoke` invalidates all device sessions and outstanding codes for the configured chain/vault. Reissuing a code rotates the unused code; it does not revoke existing device sessions.

The app bundle contains no API bearer or server RPC credential. The server stores hashes of pairing capabilities; the app stores its bounded session in Keychain. Keep the code file out of recordings and submissions. Pairing authorizes API access; financial actions still require the existing signed mandate and proof controls. A lost exchange response requires a new code. Real phone HTTPS and live settlement acceptance remain open.

`./mate stop` requests shutdown of the launcher that owns services in this checkout. The request uses a private local socket and the ownership instance; it never sends a signal to a PID read from a file. It waits for the launcher's admitted work and owned build children before reporting success. A timeout remains unconfirmed and retains ownership; it does not imply that a pending payment was cancelled. Another checkout and separately started Ollama are untouched. An older launcher without the control socket must be stopped in its original terminal with Ctrl+C.

Full-stack iPhone launch (`make dev-device`, or the iPhone choice in `make dev`) checks `MATE_API_URL` over HTTPS before building the app. It rejects localhost URLs, embedded credentials, unavailable proof verification and a mismatched chain/vault/token. This is a Mac-side connectivity check; the phone still validates its own connection during runtime pairing. The app-only launcher remains usable for offline features without a configured API. Configure the HTTPS route using [the Tailscale Serve procedure](docs/arc-setup.md#physical-iphone-https-tailscale-serve).

Provider discovery also needs a real on-chain identity and indexed metadata. `npm run register-provider` previews the public registration; `-- --submit` sends the reviewed Sepolia registration through a durable transaction journal. `npm run check-provider -- 11155111:AGENT_ID` then checks the same Graph and live-quote path used by Mate. See [provider registration and recovery](docs/provider-registration.md).
