# ETHGlobal submission copy

Prepared on 2026-09-07 for the current [review branch / PR #12](https://github.com/susumutomita/ZeroKeyMate/pull/12). The text below describes the implemented prototype. The exact event, track and partner prizes have not been supplied, so eligibility is not claimed. Final form field names and length limits must be checked in that event's Hacker Dashboard.

## Project name

ZeroKey Mate

## Short description

A private iPhone companion that proves each paid AI request follows your rules.

## Project description

AI companions can feel personal while still asking you to give up control of your conversations and your wallet. ZeroKey Mate explores a more deliberate relationship: conversation stays on your iPhone, and asking an external specialist for help becomes an explicit, bounded decision.

Mate is a native SwiftUI companion designed for an iPhone and a DockKit stand. Its current specialist tasks are Japanese-to-English translation and summarization. You review the exact text, provider, recipient and price before a request leaves the phone. An owner-approved mandate commits to a private budget and allowed services. A real ProveKit proof establishes that the concrete action complies with that policy without disclosing the policy's budget or salt.

On Ethereum, MateVault checks the owner grant, agent signature, action binding, expiry, revocation and replay before transferring test USDC. The language model cannot grant itself payment authority. The specialist prepares a result, independently verifies the canonical payment event and then releases it. If the connection fails, an encrypted journal and the same signed request allow recovery without a second payment.

The working local demonstration combines real cryptographic proofs, HTTP services, Solidity execution and an actual Ollama translation. Settlement runs on Anvil and discovery is a labeled fixture. Physical DockKit, mobile proof performance and live Privy/ENS/The Graph/public-Sepolia acceptance remain open. The proof is verified off chain by an attestor trusted by the vault; this prototype does not claim trustless on-chain ZK verification.

Further app work includes unified cancellation across pending operations, full-stack startup, runtime pairing, conversational setup and expressive stand motion. This submission describes the currently demonstrated local protocol and native UI, not completion of the entire [product backlog](validation.md#remaining-product-implementation).

## How it is made

The app uses SwiftUI, Foundation Models, on-device Speech, AVFoundation and DockKit. A shared Swift package defines the versioned mandate/action encoding and validates execution evidence. Sensor intent is separate from hardware state, so stopping during startup, backgrounding or detaching cannot silently restore capture.

A Noir circuit proves policy compliance using ProveKit. Its public action commitment binds the actual chain, vault, mandate, recipient, amount, service, expiry, replay nonce and disclosure hash. A Rust verifier checks the proof and extracts public inputs; the Node.js API compares them against the requested execution before signing an attestation. Solidity and OpenZeppelin enforce the owner/agent authority and settlement state.

Privy is the implemented wallet/signing adapter. The Graph queries provider candidates, and ENSv2 resolution is used to check their named recipients; those paths still require live validation. The specialist calls an operator-selected Ollama model without tools. Approved text and prepared results use encrypted SQLite journals. Both the specialist and iPhone verify the exact payment event; a successful transaction alone is insufficient.

Pinned dependency versions and public sources are recorded in [SOURCES](SOURCES.md). The code is Apache-2.0 with applicable dependency notices retained.

## Challenges addressed

- **Binding the proof to the action.** Swift, Noir, Node and Solidity agree on a versioned encoding. Tests reject modified proofs, changed disclosures and reuse for a different execution.
- **Recovering without spending twice.** The app keeps the exact signed submission; the server persists requests and transaction bytes. A local test closes/reopens the API and SQLite, recovers the result and verifies that the balance only decreased once.
- **Stopping real sensors predictably.** Capture intent and hardware state are separate. Late permission/startup completions cannot restore canceled consent, and OFF waits for the capture service to finish stopping.
- **Keeping the demo honest.** Source-only builds disable proving; missing integrations report unavailable. Simulated settlement and discovery fixtures are explicitly identified.

## Integration evidence for partner applications

These are implementation notes, not assertions that a partner is sponsoring the selected event or that a prize requirement is met.

| Technology | Meaningful role | Evidence to show | Current gap |
| --- | --- | --- | --- |
| ProveKit / Noir | Proves the paid action satisfies a private policy | [`circuits`](../circuits), [`services/verifier`](../services/verifier), `npm run test:proofs` | Mobile runtime/performance acceptance |
| Ethereum / test USDC | Enforces signed authority and prevents repeat spending | [`MateVault.sol`](../contracts/src/MateVault.sol), `make test-contracts`, local recovery demo | Public Sepolia contract/transaction links |
| Privy | Owner and agent wallet roles, EIP-712 signing | [`WalletService.swift`](../apps/ios/ZeroKeyMate/WalletService.swift) | Actual login and signing session |
| ENSv2 | Owner-held companion name and recipient address resolution | [`names.mjs`](../services/api/names.mjs), [`discovery.mjs`](../services/api/discovery.mjs) | Live registration and root resolution |
| The Graph | Supplies provider records used in candidate selection | [`discovery.mjs`](../services/api/discovery.mjs) | Live query, schema and resulting provider decision |

Do not use local discovery fixtures as live integration evidence. Record the actual query/transaction and the resulting app behavior before selecting a prize that requires it.

## AI assistance disclosure

Codex assisted with implementation, debugging, automated validation and this submission documentation. The repository contains the resulting source, tests, build instructions and public dependency references. The human supplied the project requirements and consent/security boundaries and requested completion, local verification and submission preparation. No independent human review, video narration or team contribution beyond what is documented is asserted. See [development history and scope](development-history.md#ai-assistance).

## Submission fields still requiring the entrant

| Field | Current value / next action |
| --- | --- |
| Event and deadline | Not supplied. Confirm the exact official event URL and dashboard deadline. |
| Track and eligible new work | Not selected. Map [existing commits](development-history.md) to the event's start/end window; disclose pre-existing work. |
| Team members and contribution statements | Not supplied. Use each entrant's actual name, role and work. |
| Repository | [ZeroKeyMate](https://github.com/susumutomita/ZeroKeyMate); currently submit the [review branch](https://github.com/susumutomita/ZeroKeyMate/tree/codex/complete-local-runtime) / exact reviewed commit, not an older main. |
| Demo video | Not recorded/uploaded. [Three-minute script and capture plan](demo.md). |
| App / deployment link | No public install or live deployment claimed. Provide source/build instructions, and add verified testnet links if deployed. |
| Partner prizes and feedback | Not selected. Match actual integrations to the selected event's official requirements and record real feedback. |
| AI/spec workflow disclosure | This document and [development history](development-history.md); add any earlier prompts/specs actually used before final submission. |

## Official rules to check

ETHGlobal's [ETHOnline 2026 submission guide](https://ethglobal.com/events/ethonline2026/info/details) was consulted on 2026-09-07 as a concrete example. It distinguishes new work from continuity, asks for AI attribution and requires a 2–4 minute demo. **This does not select ETHOnline as the submission event.** Follow the actual event's rules and partner terms; they may differ. The [official events list](https://ethglobal.com/events) is the starting point.

This package has not been submitted to an organizer or Hacker Dashboard.
