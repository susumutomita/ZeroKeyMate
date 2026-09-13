# Development history and attribution

This record distinguishes repository history, third-party dependencies and AI assistance. The entry is for ETHOnline 2026; the dashboard shows from-scratch project rules. This record does not independently certify track eligibility. Commit timestamps are evidence of recorded history, not independent proof of when every line was authored.

## Existing history

Times below are the recorded author times in JST (UTC+09:00). The history has been preserved.

| Commit | Recorded date | Scope recorded by the commit |
| --- | --- | --- |
| [`6e172d6`](https://github.com/susumutomita/ZeroKeyMate/commit/6e172d6) | 2026-09-05 08:32 | Initial commit |
| [`9e6d92f`](https://github.com/susumutomita/ZeroKeyMate/commit/9e6d92f) | 2026-09-05 14:41 | Native iOS foundation, camera consent and DockKit, PR #1 |
| [`8d8b271`](https://github.com/susumutomita/ZeroKeyMate/commit/8d8b271) | 2026-09-06 14:49 | Implementation import and partial 0.3.0 API delivery, PR #2 |
| [`addcbb1`](https://github.com/susumutomita/ZeroKeyMate/commit/addcbb1) | 2026-09-06 22:55 | Local execution API/specialist, naming, recovery and build/validation setup |
| [`cdfb6d0`](https://github.com/susumutomita/ZeroKeyMate/commit/cdfb6d0) | 2026-09-06 23:51 | Readable Japanese accessibility label for the brand |
| [`5bbe0f6`](https://github.com/susumutomita/ZeroKeyMate/commit/5bbe0f6) | 2026-09-07 10:08 | Full icon-button hit regions and UI interaction checks |

Later implementation continues in the preserved Git history. [PR #49](https://github.com/susumutomita/ZeroKeyMate/pull/49) adds the prepared Arc history Subgraph; [PR #50](https://github.com/susumutomita/ZeroKeyMate/pull/50) completes the physical-card age-proof checkout and English purchase controls. PR #50 merged as `ef2cd7b9922a23e9bd6a1ba4c8935c5a0c270759`. [PR #52](https://github.com/susumutomita/ZeroKeyMate/pull/52) records repeated payments, transient shop-readiness recovery and the current submission materials. Use its final merged revision once available; PR #12 is historical, not the current acceptance build.

The human designed the companion use case and privacy/authorization constraints, repeatedly tested the real iPhone and stand, performed My Number card authentication and exact payment approvals, reported UX failures, confirmed purchases and supplied the demo footage and screenshots. Codex assisted with the corresponding implementation and fixes. Public CircuitBreaker NFC code is attributed as reused work, rather than claimed as a new invention. AI-generated logo and cover artwork are identified separately from actual app screenshots and transaction evidence.

Commit dates and dependency licenses are not sufficient to establish from-scratch eligibility. Preserve and disclose the real baseline and any pre-existing project work; no history has been rewritten to fit the event.

## Public dependencies

The project uses public libraries and APIs, including Privy, Verity/ProveKit, Noir SHA-256, OpenZeppelin, viem and platform SDKs. Their reviewed versions, licenses and sources are in [SOURCES](SOURCES.md), [dependency inventory](dependencies.json) and [notices](THIRD_PARTY_NOTICES.txt). Those are reused dependencies, not original hackathon inventions. Model weights are not included.

The implementation follows this repository's [development boundaries](../AGENTS.md). Unrelated private repositories and earlier private-code excerpts were not used as implementation sources in this completion work. A source/license record is not a formal clean-room audit.

## AI assistance

Codex assisted with code, debugging, tests, public-documentation research, build configuration and submission writing. The completion work includes these areas:

| Area | AI-assisted work recorded in this completion session |
| --- | --- |
| `services/api`, `services/provider`, `services/verifier` | Execution services, name registration, proof verification, encrypted recovery and tests |
| `apps/ios/ZeroKeyMate`, `Sources/MateCore`, tests | Request/receipt recovery, lifecycle handling, native integration, accessible controls and regression checks |
| `contracts`, `scripts`, workflows, manifests | Resolver support, build/setup and acceptance tooling, dependency/source records |
| README and `docs` | Technical explanation, validation record, demo script and submission copy |

The human supplied the requirements and consent/security constraints, requested completion and local operation checks, authorized pushing code and starting the Simulator, and asked for ETHGlobal submission materials. Human team roles, independent review and video narration have not been inferred from repository ownership. The entrant must add an accurate personal contribution statement and disclose any earlier AI work before final submission.

The task brief available for this work is the root [AGENTS.md](../AGENTS.md) and the requested outcomes: complete the project, check local behavior, push changes, and prepare the README/materials for ETHGlobal. The implementation constraints include explicit sensor consent, versioned financial authorization, actual proof verification and truthful unavailable states. No spec-framework history or complete earlier prompt transcript is claimed here. If a spec-driven workflow or other prompts were used earlier, include the actual project artifacts required by the selected event without publishing secrets or unrelated private content.
