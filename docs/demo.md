# Three-minute demo guide

One story: **an iPhone proves a paid translation follows a private policy, and another machine can check the proof without receiving that policy.** The **Settings → Try private rules on this device** entry exercises the production native circuit before any wallet setup. Actual phone performance, export and the complete mobile payment path still require acceptance; do not splice terminal results into an apparent live phone transaction.

Lead with the local proof, not the eyes or stand. Use an installed native build, show airplane mode, enter a private limit and public quote, and generate a proof. Keep the real elapsed time visible. Share the `.np` file explicitly, transfer it to the verification computer and run the README's verification command using the matching setup key. This is the proposed strongest demonstration; it is not yet recorded device evidence. If device acceptance is unavailable, present the terminal proof segment as a terminal segment.

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

Before recording, verify the exact installed build opens on the target phone. Existing screenshots are CI Simulator attachments, not physical-device footage. Keep actual phone, Simulator and local-chain segments explicitly labeled. A successful device install does not establish voice, stand, offline or payment acceptance.

## Recording sequence and narration

| Time | Show | Suggested human narration |
| --- | --- | --- |
| 0:00–0:20 | Native app's Local ZK screen; actual device and airplane-mode state | “This iPhone can prove a request follows my private spending rules. The verifier does not need my total budget or full permission list.” |
| 0:20–1:10 | Enter private limit and public price, then run real local proving | “This is our production ProveKit circuit. No wallet is connected for this offline exercise. Here are the actual proof size and time measured on this device.” |
| 1:10–1:40 | Export the actual proof and verify it on another computer | “This file came from the phone. A separate verifier accepts it with the matching circuit key. The modified copy is rejected by the app's native verifier.” |
| 1:40–2:00 | Change the permission to forbid translation, then request proof generation | “Mate refuses at preflight. That refusal is not itself a ZK proof. Cryptographic enforcement also requires the circuit and independent verifier.” |
| 2:00–2:40 | Separately labeled `test:local` result and recovery assertions | “In this local payment simulation, a real proof binds the approved text, recipient and price. The vault prevents replay, and retry retrieves the same result without another payment. Discovery is a fixture.” |
| 2:40–3:00 | Actual acceptance status and trust boundary | “Our goal is private permission for paid AI requests. Today settlement trusts the server verifier's attestation. Full phone-to-live-service payment and physical hardware acceptance remain open.” |

If the real-model mode was not run, say “model fixture” in the narration and do not display the earlier translation as a new result. Do not imply the test output is a live phone transaction. The 9.9 balance is asserted by the test; it is not currently a dedicated UI or receipt display.

## Evidence to keep on screen

- The command and its actual successful exit, including whether the test says `actual Ollama` or `model fixture`.
- The `LOCAL PAYMENT SIMULATION` context: Anvil, test token, published test accounts; no public Arc or Sepolia explorer link.
- The [recovery assertions](../services/api/test/local.acceptance.mjs): reconstructed API/journal, identical receipt, owner balance `9_900_000` and model invocation count `1`.
- The [proof-boundary tests](../services/api/test/crypto.acceptance.mjs), with actual verifier use and rejection results.
- A source commit and [validation record](validation.md) matching the footage. Keep credentials, `.env`, pairing tokens and private keys out of the recording.

The screenshots in [assets](assets/README.md) are genuine test attachments. They can support an explanation but are not a substitute for the executable demonstration.

For the UI segment: [home](assets/home-simulator.png), [Rest](assets/rest-simulator.png), [empty conversation](assets/conversation-simulator.png), and [settings](assets/settings-simulator.png). Label them “CI iOS Simulator — source-only build” when presenting them as still images.

## Video format and judge questions

Target a three-minute, at least 720p desktop capture with the entrant's own narration. Remove idle waits with visible cuts; keep the actual execution order and result. Use screen capture for the iPhone/Simulator rather than filming a display with a phone. The consulted [ETHOnline 2026 guide](https://ethglobal.com/events/ethonline2026/info/details) requires 2–4 minutes and disallows sped-up footage and AI/TTS narration. ETHOnline 2026 is the confirmed event. Recheck the current organizer requirements before exporting.

Be ready to answer:

- **Who enforces the private budget?** The trusted ProveKit verifier/attestor checks it. The contract independently enforces grant/action signatures, expiry, revocation and replay. A colluding attestor and agent can exceed the private budget.
- **What is private?** Budget, allowed-service mask, salt and local conversation are withheld. The approved text goes to the specialist; payment metadata is public. Server operators can decrypt their journals.
- **What if the provider disappears after payment?** Stored requests/results support recovery, but this is not escrow and there is no automatic refund.
- **Why Arc, Privy and The Graph?** Arc Testnet is the implemented settlement target (public acceptance pending), Privy supplies owner and execution wallets, and The Graph supplies provider candidates. Full live acceptance remains pending; provider discovery never gives spending authority. ENS is deferred.
- **Did this run on DockKit hardware?** No physical acceptance has been recorded. Build, Simulator and local-chain evidence are listed separately.
