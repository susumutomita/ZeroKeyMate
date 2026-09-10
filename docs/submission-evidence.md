# Submission requirements and evidence

Checked 2026-09-10. This is a preparation matrix for Issue #18, not an eligibility decision or submission receipt. The entry must use one final merged commit and footage of that build.

## Organizer requirements

The [ETHOnline guide](https://ethglobal.com/events/ethonline2026/info/details) sets the deadline at **2026-09-13 12:00 EDT**, equivalent to **16:00 UTC / 2026-09-14 01:00 JST**. Submit through the Hacker Dashboard. Up to three partner prizes can be selected. The video must run 2–4 minutes, be at least 720p and use human narration; sped-up footage and AI/TTS voiceover are disallowed. Disclose AI assistance, retained specs/prompts and pre-existing work according to the chosen pool.

| Deliverable | Repository preparation | Remaining acceptance |
| --- | --- | --- |
| Description and technical explanation | [English copy](submission.md), [architecture](architecture.md) | Check actual form fields/lengths and final build claims |
| New-work and AI attribution | [Development history](development-history.md) | Entrant reviews contribution statements and track eligibility |
| 2–4 minute human-narrated video | [Recording sequence](demo.md) | Record real footage, export, play the whole file, upload and verify playback |
| Reproducible public source | Main includes launcher, pairing and companion implementation | Clean-checkout rehearsal using the final commit and documented prerequisites |
| Entry submission | Copy and evidence plan prepared | Entrant identity, selected prizes, final authorization, submit and reload-confirm receipt |

## Partner-specific proof

These targets are recommendations. No live partner integration is marked accepted merely because its adapter compiles.

| Proposed prize | Required role and artifact | Outstanding work |
| --- | --- | --- |
| [Arc: Best Agentic Economy Application with Circle Agent Stack](https://ethglobal.com/events/ethonline2026/prizes/arc) | Working frontend/backend, architecture diagram, documented demonstration of agents using Circle Agent Stack and USDC transactions on Arc | #16 accounts, deployment and funding; #17 actual phone proof, payment, result and retry evidence. The prize page conditions part of its award on deployment to Arc Mainnet by September 30; this is not authorization for mainnet spending/deployment. |
| [Privy: Best financial flow](https://ethglobal.com/events/ethonline2026/prizes/privy) | Privy central to the experience, an actual Privy wallet and a functional financial flow using a generally available feature, demonstrated with public source | #16 actual login/wallet; #17 successful wallet action in the phone journey. A mocked commercial-onboarding feature cannot satisfy the required integration. |
| [The Graph: Best AI Tooling or AI Use Case](https://ethglobal.com/events/ethonline2026/prizes/the-graph) | Live Graph data must drive meaningful reasoning, selection or automation; source and demo must be public, and the pool must match prior work | #16 actual indexed provider and live query; #17 show the query affecting specialist selection. Local/static fixtures and printing a raw query are insufficient. |

ENS is deferred. ProveKit private-policy proofs are not identity verification, and a proof alone does not establish a partner prize's eligibility.

## Freeze the evidence before recording

Keep a local record outside version control containing the final source commit, build/setup hashes, recording date, actual device/OS, command outcomes and reviewed public transaction links. Do not include credentials, raw conversation or private policy values in published evidence. Missing fields stay missing; no invented timing, transaction or provider is permitted.

The video can combine an explicitly labeled physical companion segment, an offline proof segment and a local payment simulation. It must not make those separate recordings look like one live phone-to-Arc transaction. If #17 remains open, say so in the narration and assess whether the proposed partner requirements are actually met.

After the entrant supplies the human-narrated video and confirms the final fields, check links and video playback in the reviewable form. Only a submitted state confirmed after reload closes the final-submission portion of #18. Nothing in this document records that outcome.
