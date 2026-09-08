# ZeroKey Mate — interim progress report

Prepared 2026-09-07. **Submitted, as reported by the entrant on 2026-09-07; receipt not independently checked.** The event is confirmed as ETHOnline 2026. The first check-in form is https://ethglobal.com/events/ethonline2026/check-in?step=1; its deadline was not shown in the form. This is a factual report body; replace form headings/lengths when the actual form is available. Do not include this preparation note in the submitted description.

## Project

**ZeroKey Mate — Your companion. Your rules.**

We are building an iPhone desk companion that keeps everyday conversation on-device and makes paid requests to external AI specialists subject to the owner's private spending rules. A representative use case is translating a Japanese meeting note for an overseas teammate: the user reviews exactly what text leaves the phone and the quoted price, then authorizes the task within a bounded mandate.

A compatible DockKit stand supports the physical companion experience. It is optional for the proof/payment protocol. Camera and microphone require explicit starts; docking or charging is not consent to record or pay.

## Progress

- Implemented an English native SwiftUI interface, explicit sensor controls, typed/voice conversation adapters and a launch menu for Simulator or a connected iPhone. The user has reported seeing the app's eye screen; that alone is not validation of conversation, proving or stand tracking.
- Implemented private policy/action encoding, a Noir circuit and real ProveKit proving/verification. A fresh proof was generated and verified locally on the Mac on September 7 using the prepared circuit artifacts. These artifacts were integrity-checked; this run does not claim fresh circuit compilation or iPhone proving performance.
- Implemented a real Rust verifier, authenticated API, specialist service, Solidity vault and encrypted restart/retry journals. Earlier local integration acceptance exercised proof verification, HTTP, contract settlement and result recovery without duplicate spending. Payments used a disposable Anvil chain and discovery used labeled fixtures. A separate local evaluation used an actual installed Ollama model.
- English-interface commit `07d2fe5` passed iOS/enforcement CI and cryptographic acceptance. Local unit tests total 46 (19 Swift, 22 Node, 5 launcher tests). Native iOS proof tests are skipped in the source-only baseline CI, so those CI results are not evidence of on-device proving.
- Documented use cases, architecture, setup, stopping behavior, trust assumptions, dependency provenance, AI assistance and a proposed delivery schedule.

## Current limitations and next milestone

The UI does not yet guide a first-time user through one complete translation. The next milestone is a connected flow: enter text → review provider/text/price → complete necessary setup and approve a mandate → generate a real proof → execute → show the result and recoverable receipt.

Remaining work includes cancellation correctness across pending operations, the necessary app/service connection setup, actual Privy and live discovery/naming acceptance, target-iPhone proof time/memory measurement, and physical camera/microphone/DockKit tests. Broader conversational setup and expressive stand motion remain outside the minimal demonstration until the core flow works.

The private budget is checked by an off-chain proof verifier/attestor trusted by the vault. The contract independently checks signed authority and replay; this is not trustless on-chain ZK verification. The approved text goes to the specialist, and payment recipients/amounts are public. No production funds or identity-card functionality are included.

## Proposed prizes and delivery

The user-approved priority is Arc/Circle Agent Stack, Privy financial flow, then The Graph AI use case. Arc integration is planned and unimplemented; ENSv2 is deferred. No prize eligibility or final selection is claimed yet. See the [requirements/evidence matrix](prize-strategy.md).

The proposed delivery plan completes the essential mobile flow by September 10, freezes the demonstrated scope on September 11, records a three-minute human-narrated English demo on September 12 and targets submission on September 13 at 18:00 JST. The actual event and interim-report deadline must be confirmed; these dates are planning targets. If mobile/live acceptance remains blocked, the presentation will explicitly separate app UI from the verified local protocol demonstration.

## Evidence and contribution record

- [Repository](https://github.com/susumutomita/ZeroKeyMate), [review branch / PR #12](https://github.com/susumutomita/ZeroKeyMate/pull/12)
- [English-interface CI](https://github.com/susumutomita/ZeroKeyMate/actions/runs/34094233861), [cryptographic CI](https://github.com/susumutomita/ZeroKeyMate/actions/runs/34094233863)
- [Validation](validation.md), [development and AI attribution](development-history.md), [schedule](schedule.md)

Codex assisted with implementation, debugging, tests and documentation. The human supplied requirements, product direction and consent boundaries. Team names and individual contribution details must come from the entrant; this report does not invent them.

## Submission tracking

| Item | Status |
| --- | --- |
| Actual event / entrant pool | ETHOnline 2026 / Building from Scratch, observed in dashboard |
| Interim-report form and deadline | Check-in 1 found and filled; deadline not shown |
| Report body | Prepared above |
| Prize strategy | Proposed, evidence gaps recorded |
| Form submission / receipt | Submitted, as reported by the entrant on 2026-09-07. Submission receipt not independently checked. |

## Implementation update after the submitted check-in

Arc settlement binding, Circle Agent Wallet proof-attestation adapter, validated runtime connection settings and foreground full-stack startup are now implemented. The earlier report above is preserved as a dated status, not rewritten as if these features existed at submission. Live Circle/Privy/Graph acceptance and the physical-iPhone proof-to-payment flow remain pending.
