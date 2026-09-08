# Prize strategy

Reviewed 2026-09-07. **ETHOnline 2026 attendance and the selected Building from Scratch pool were confirmed in the entrant's dashboard. Final prize selection/submission remains incomplete.** The ordering below is an engineering recommendation based on the current product, not an eligibility determination. Confirm the event and the entrant's Start Fresh/Continuity pool before final selection.

| Priority | Target | Why it fits Mate | Required evidence still missing |
| --- | --- | --- | --- |
| 1 | Arc — Best Agentic Economy Application with Circle Agent Stack | The user selected Arc as the intended USDC settlement layer for bounded specialist requests | Arc settlement binding and Circle Agent Wallet proof-attestation adapter are implemented and locally tested; actual Circle login, public vault and live settlement evidence remain required |
| 2 | Privy — Best financial flow ($2,500) | Owner authentication and separate owner/agent wallets support the central paid-specialist journey | A real Privy wallet and a working supported financial operation, demonstrated through the app; compile-only adapter evidence is insufficient |
| 3 | The Graph — Best AI Tooling or AI Use Case with The Graph | Live provider data can determine which specialist the user chooses | A live Graph query affecting provider selection, with actual records and reproducible evidence; local discovery fixtures do not qualify |
| Deferred | ENS — Best Use of ENSv2 | A managed companion subname and checked provider recipient can make names functional parts of the journey | Working ENSv2 on Sepolia, real registration/resolution and a demonstrable product benefit beyond displaying a name |

Official requirements: [Arc](https://ethglobal.com/events/ethonline2026/prizes/arc), [Privy](https://ethglobal.com/events/ethonline2026/prizes/privy), [The Graph](https://ethglobal.com/events/ethonline2026/prizes/the-graph), [ENS](https://ethglobal.com/events/ethonline2026/prizes/ens). Graph has separate Start Fresh and Continuity pools. ENS also lists an existing-project integration prize; choose the applicable category only after the entrant's pool and prior work are confirmed.

The first priority is to complete the paid translation journey on Arc with Circle Agent Stack. Graph is useful only if its records affect a real choice. ENS is the first prize to drop if completing it would jeopardize the core demo. Do not add unrelated sponsor SDKs to fill application slots.

## What we are not claiming

The [World prize page](https://ethglobal.com/events/ethonline2026/prizes/world) describes AgentKit and Selfie Check integrations. Our private-policy ProveKit implementation is not evidence of either. Client-side ZK remains our core technical contribution, but it does not by itself establish eligibility for a World prize. We found no separately named ProveKit prize in the consulted [event prize listing](https://ethglobal.com/events/ethonline2026/prizes).

The repository now supports Arc Testnet and legacy Sepolia, with real local proof/contract acceptance on both chain domains. Public Arc/Circle operation is not yet demonstrated; Ledger and Chainlink are not current targets. No standalone Belkin prize was identified in that listing.

## Decision before final submission

1. Confirm the actual event, pool and admissible pre-existing work using the entrant's dashboard and contribution history.
2. Implement and record Arc/Circle Agent Stack settlement and the real Privy flow. Keep its wallet and transaction evidence with the final commit.
3. Demonstrate Graph provider selection on live data; retain a sanitized query/result and the resulting decision.
4. Include ENS only when its real Sepolia path and central product value are shown.
5. Draft sponsor feedback from actual integration experience, then choose only supported prizes in the submission form.

Until those gates pass, the interim report should say “proposed targets” and “live acceptance pending.” Missing integration evidence must not become a successful-looking UI or a fabricated transaction.
