# Three-minute demo guide

One story: **approve a bounded translation, obtain its result, then retry without paying twice.** Use the native app for the consent/UI segment and the actual local acceptance harness for the cryptographic/payment segment. The full iPhone-to-live-services flow has not passed acceptance, so do not splice those segments into an apparent live mobile payment.

This is a recording plan, not a completed video. [Submission fields](submission.md#submission-fields-still-requiring-the-entrant).

## Prepare the demo

Follow the [README](../README.md#run-the-app) first. For the proof/payment segment, install Rust/rustup and Foundry (`anvil` on PATH), then run:

```sh
make test-contracts
make proofs
cargo +nightly-2026-03-04 build --release --locked --manifest-path services/verifier/Cargo.toml
npm run test:proofs
npm run test:local
```

`test:local` starts and cleans up a disposable local chain, API and specialist. It uses Anvil's published test accounts and a test token. No public transaction is sent. Its default model output and discovery records are labeled fixtures; proof generation, signatures, HTTP, contract execution and recovery are real.

For the strongest currently reproducible segment, start Ollama separately with an already installed model whose license permits your intended use. Then select it explicitly:

```sh
MATE_TEST_OLLAMA_MODEL=YOUR_INSTALLED_MODEL \
MATE_TEST_OLLAMA_URL=http://127.0.0.1:11434 npm run test:local
```

Replace `YOUR_INSTALLED_MODEL` with the actual model name. This mode fails when the model is unavailable; it does not fall back to a canned response or download weights. Discovery remains a fixture and settlement remains Anvil simulation. The recorded local research evaluation used `qwen2.5:3b`; its license is not a blanket permission for deployment or redistribution. [Evaluation details](validation.md#push前のローカル実動確認) and [CPU setup (日本語)](setup.md#実モデルを使うローカル動作確認).

Before recording, verify the target Simulator/device actually opens the app. In this managed local environment Simulator access was blocked, so the committed screenshots come from this repository's CI Simulator. Do not describe those captures as physical-device footage. If local access is still blocked, use the attributed CI captures for the UI explanation and label the runnable terminal segment separately.

## Recording sequence and narration

| Time | Show | Suggested human narration |
| --- | --- | --- |
| 0:00–0:20 | Actual app home or attributed CI capture | “This is Mate, an iPhone companion built around your consent. Conversation is designed to stay on the phone. Asking an outside AI for help is a separate decision.” |
| 0:20–0:45 | Conversation/settings screen; camera stays off. Show Rest only if actually operating the app. | “You choose what to share and approve a spending policy. Docking never starts a recording or a payment. The current UI is Japanese; these are conversation, talk and rest.” |
| 0:45–1:05 | README architecture and the test's approved sentence | “Let's translate one meeting note. This next segment is our local protocol demo: a real proof and model, with simulated payment on Anvil. Provider discovery uses test data.” |
| 1:05–1:45 | Run the actual-model `test:local` command and show its real result | “The proof binds this exact text, recipient and amount to an approved policy. The API verifies it; the contract checks authority and replay. The specialist checks the payment event before releasing this translation.” |
| 1:45–2:15 | Explain the restart/retry assertions in `local.acceptance.mjs` alongside the passing run | “The same test then closes the API and database, starts them again and retrieves this result. It resubmits the original request. The balance is still 9.9 test tokens from an initial 10, and the model ran once.” |
| 2:15–2:40 | `npm run test:proofs`; show tamper/substitution tests pass | “A modified proof or proof for another action is rejected. The private budget and salt are not part of the public grant; the amount and recipient are public.” |
| 2:40–3:00 | Validation/status table | “Today this works locally. Hardware and live integrations are next. The vault trusts an off-chain proof attestor. Our contribution is a companion whose paid requests are explicit, bounded and recoverable.” |

If the real-model mode was not run, say “model fixture” in the narration and do not display the earlier translation as a new result. Do not imply the test output is a live phone transaction. The 9.9 balance is asserted by the test; it is not currently a dedicated UI or receipt display.

## Evidence to keep on screen

- The command and its actual successful exit, including whether the test says `actual Ollama` or `model fixture`.
- The `LOCAL PAYMENT SIMULATION` context: Anvil, test token, published test accounts; no public Sepolia explorer link.
- The [recovery assertions](../services/api/test/local.acceptance.mjs): reconstructed API/journal, identical receipt, owner balance `9_900_000` and model invocation count `1`.
- The [proof-boundary tests](../services/api/test/crypto.acceptance.mjs), with actual verifier use and rejection results.
- A source commit and [validation record](validation.md) matching the footage. Keep credentials, `.env`, pairing tokens and private keys out of the recording.

The screenshots in [assets](assets/README.md) are genuine test attachments. They can support an explanation but are not a substitute for the executable demonstration.

For the UI segment: [home](assets/home-simulator.png), [Rest](assets/rest-simulator.png), [empty conversation](assets/conversation-simulator.png), and [settings](assets/settings-simulator.png). Label them “CI iOS Simulator — source-only build” when presenting them as still images.

## Video format and judge questions

Target a three-minute, at least 720p desktop capture with the entrant's own narration. Remove idle waits with visible cuts; keep the actual execution order and result. Use screen capture for the iPhone/Simulator rather than filming a display with a phone. The consulted [ETHOnline 2026 guide](https://ethglobal.com/events/ethonline2026/info/details) requires 2–4 minutes and disallows sped-up footage and AI/TTS narration. Confirm the selected event's rules before exporting; no event is selected in this repository yet.

Be ready to answer:

- **Who enforces the private budget?** The trusted ProveKit verifier/attestor checks it. The contract independently enforces grant/action signatures, expiry, revocation and replay. A colluding attestor and agent can exceed the private budget.
- **What is private?** Budget, allowed-service mask, salt and local conversation are withheld. The approved text goes to the specialist; payment metadata is public. Server operators can decrypt their journals.
- **What if the provider disappears after payment?** Stored requests/results support recovery, but this is not escrow and there is no automatic refund.
- **Why The Graph and ENS?** Live records are intended to select a specialist and verify its named recipient. Their live acceptance is still pending; neither gives spending authority.
- **Did this run on DockKit hardware?** No physical acceptance has been recorded. Build, Simulator and local-chain evidence are listed separately.
