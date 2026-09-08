# Development history and attribution

This record distinguishes repository history, third-party dependencies and AI assistance. It does not certify eligibility for an event whose dates/track have not been supplied. Commit timestamps are evidence of recorded history, not independent proof of when every line was authored.

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

The submission materials and final validation update are subsequent changes in [PR #12](https://github.com/susumutomita/ZeroKeyMate/pull/12). Use its final commit when recording/submitting. The earlier import is visible in the history; this document does not turn it into a claim of development during an unconfirmed event.

Once the event is known, record its official start/end times, selected track, baseline commit and the precise new work completed during that window. Obtain any required eligibility clarification from the event before claiming an applicable category. No history has been rewritten to fit a hackathon window.

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
