# ETHOnline 2026 submission draft

Current story: the physical-card age proof and Arc test purchase. Updated September 13, 2026. **This is prepared copy, not a submitted entry.** The final video URL and dashboard receipt are still missing. Use [live evidence](arc-live-status.md), [the four-minute plan](demo.md), and [prize requirements](prize-strategy.md).

## Project name

ZeroKey Mate

## Short description

An iPhone companion that proves your age privately and pays on Arc.

## Description

ZeroKey Mate turns an iPhone into a companion that helps you act while keeping identity details private. Ask Mate for a beer. The on-device model proposes the supported order, while application code controls identity verification and payment.

The phone authenticates a physical Japanese My Number card and creates an order-bound zero-knowledge proof that the cardholder is at least twenty. The shop receives the proof, not the card certificate, signature, name or date of birth. A deployed Age Gate contract verifies the proof before checkout proceeds. After the user's exact approval, a Privy embedded wallet signs a 0.10 test-USDC authorization and the shop settles through x402 on Arc Testnet.

A user-operated physical-card purchase completed on September 13, with 12.0 seconds of local age-proof processing shown by the phone and a confirmed public Arc transaction. Voice opening checkout is also user-confirmed; the supplied device video combines successful recorded takes. This is testnet only, with no real money or delivery.

## How it is made

The native app uses SwiftUI, Apple Foundation Models, on-device Speech, AVFoundation, DockKit and CoreNFC. Camera capture stops before NFC begins. The model receives no card fields or signing interface. Deterministic code constrains the current purchase to one product, merchant, network and amount.

Swift authenticates the signed JPKI credential against pinned government roots and prepares the private witness. A Noir age circuit uses a pinned experimental ProveKit Groth16 backend and an EVM exporter. The proof binds the signed age condition to the specific order and nonce. Both circuit and Swift parser handle the mandatory critical signing-certificate policy; negative tests reject altered inputs, unsupported policies and invalid proofs.

A Cloudflare Worker, D1 database and Durable Object operate the store. The Worker verifies the age proof against the pinned Arc contract through two independent RPC providers before returning x402 payment requirements. Privy's iOS SDK signs the exact EIP-712 USDC authorization. The merchant sponsors gas and persists signed transaction bytes before broadcast. Receipt checks and recovery retain the original order rather than assuming a transaction hash means payment succeeded.

Age verification is an eth_call enforced by the Worker, not an atomic age-check-and-transfer contract or a permission validator. The setup is experimental and single-party; certificate revocation is not checked. The phone's wallet authentication and payment still need network services.

## Challenges solved

- A physical signing certificate exposed a mandatory critical extension missing from the original synthetic fixture. We reproduced the failure, corrected the circuit and parser, regenerated the matching setup/verifier, and completed a real-card purchase.
- DockKit motor commands could delay camera shutdown and prevent NFC from starting. Camera lifetime now stops independently, and NFC activation has explicit deadlines and cancellation.
- Uncertain proof/payment outcomes previously led to confusing retries. The app now distinguishes proof generation, age verification and payment completion, retaining the original order and exact authorization.
- The purchase interface now has a direct English/Japanese switch, short stage-specific guidance and a transaction explorer link. A physical-phone readiness probe reproduced a transient store network failure; bounded public-read retries address it without retrying payments.

## Partner application copy

### Privy — Best financial flow

Privy's iOS SDK provides the buyer's embedded wallet and signs the exact EIP-712 authorization for a 0.10 test-USDC purchase. The user can connect through email within the order flow and does not need to import a seed phrase or switch to a separate wallet app. Privy is part of the actual completed payment, not a mock.

The app restricts the signing domain to Arc Testnet and its USDC contract, and binds recipient, amount and nonce. We validate the resulting receipt before showing completion. [Confirmed purchase](https://testnet.arcscan.app/tx/0xfe77313324c3438cfc935dd87c14efe56bc6f3a1a4a4150a9ee661c045856eb3).

Feedback from this integration: a complete mobile EIP-712 example including the encoded domain would make token-authorization integration easier. Keeping email verification and wallet preparation inside the current order was important for the companion experience.

### Arc — Best DeFi/Onchain Finance Application

Mate implements an age-conditioned USDC payment on Arc Testnet. The phone creates a private age proof, the Worker checks a deployed verifier and government-root age gate, and an x402 exact authorization then settles a real 0.10 test-USDC transfer. The merchant sponsors network gas. Persistent order and transaction recovery prevent an uncertain response from becoming a new payment.

The working frontend/backend, architecture diagram and [public contract/receipt evidence](arc-live-status.md) show Arc and USDC as the actual execution path. This application targets the payment/conditional-flow category. It does not claim Circle Agent Stack integration in this checkout, or deployment on mainnet.

Feedback from this integration: x402 protocol compatibility did not provide a ready Arc facilitator, so we implemented a tightly constrained merchant sponsor. Clear examples for Arc's native-USDC fees, ERC-20 event emitter and exact-authorization recovery were important to validate the receipt correctly.

### The Graph — not ready to select

The Arc purchase-history Subgraph is prepared and merged, but it is not deployed to Studio or used by Mate for a live decision. The intended use is to read indexed spending and decide whether a new purchase fits an explicitly set local allowance. Do not paste this plan as a completed sponsor integration. Select The Graph only after a live deployment, query and meaningful change in agent behavior are demonstrated.

## AI and reused-work disclosure

The human defined the companion experience, local-model requirement, privacy and authorization boundaries, supplied repeated physical-device feedback, operated the identity card and wallet approvals, and confirmed the real purchase. Codex assisted with implementation, debugging, regression tests, deployment preparation and documentation. ChatGPT assisted with public technical research; technical claims were checked against source code and primary documentation.

The project reuses attributed public dependencies, including the MIT-licensed CircuitBreaker NFC module, ProveKit/Noir components, Privy, x402 and platform SDKs. Those components are not claimed as original hackathon inventions. See [development history](development-history.md), [sources](SOURCES.md) and [third-party notices](THIRD_PARTY_NOTICES.txt). Confirm the entrant's selected pool and admissible prior work in the dashboard before submitting; commit history and source licenses do not independently determine eligibility.

## Remaining fields and final checks

| Field | Current value / action |
| --- | --- |
| Repository | https://github.com/susumutomita/ZeroKeyMate — use the final merged revision matching the take |
| App / store | [Project LP](https://zerokeymate-arc-shop.oyster880.workers.dev/demo/) · https://zerokeymate-arc-shop.oyster880.workers.dev/ — native iPhone is required for the card flow |
| Demo video | 58.5-second edited walkthrough prepared; final 2–4-minute human-narrated export and upload remain |
| Selected prizes | Recommended: Privy financial flow and Arc DeFi/Onchain Finance; Graph remains incomplete |
| Entrant / track / prior work | Verify current dashboard values and contribution statement |
| Final submission receipt | Not submitted; reload-confirm the organizer's submitted state after the completed form is sent |

The deadline is **September 14, 2026 at 01:00 JST** (September 13 at 12:00 EDT). Up to three partner prizes may be selected. Arc attaches a September 30 mainnet condition to part of its award; the current app, evidence and authorization are testnet only. [Official submission guide](https://ethglobal.com/events/ethonline2026/info/details).
