# Prize strategy

Updated for the fixed-store purchase flow on 2026-09-13. **ETHOnline 2026 attendance and the selected Building from Scratch pool were previously confirmed in the entrant's dashboard. Final prize selection/submission remains incomplete.** These are targets, not achieved integrations or an eligibility determination. Use [current public deployment evidence](arc-live-status.md); earlier private-policy/specialist adapters are separate from the age checkout.

| Priority | Target | Why it fits Mate | Required evidence still missing |
| --- | --- | --- | --- |
| 1 | Arc — Best Agentic Economy Application with Circle Agent Stack | The on-device agent orders from the prepared store and pays test USDC after age verification | Contracts, store and sponsor funding are live. Actual buyer settlement and meaningful Agent Stack use in this checkout remain missing; the old vault attestor does not establish them |
| 2 | Privy — Best financial flow ($2,500) | The buyer's Privy wallet signs the exact x402 authorization | An actual supported wallet action in the complete physical-phone purchase, with a confirmed buyer payment; compile-only evidence is insufficient |
| 3 | The Graph — Best AI Tooling or AI Use Case with The Graph | Live Arc payment history could inform the local agent's remaining-budget decision | This is a proposed integration, not implemented in the beer flow. Deploy/query a real Subgraph and demonstrate a changed decision; static data and the earlier specialist adapter do not qualify |
| Deferred | ENS — Best Use of ENSv2 | A managed companion subname and checked provider recipient can make names functional parts of the journey | Working ENSv2 on Sepolia, real registration/resolution and a demonstrable product benefit beyond displaying a name |

Official requirements: [Arc](https://ethglobal.com/events/ethonline2026/prizes/arc), [Privy](https://ethglobal.com/events/ethonline2026/prizes/privy), [The Graph](https://ethglobal.com/events/ethonline2026/prizes/the-graph), [ENS](https://ethglobal.com/events/ethonline2026/prizes/ens). Graph has separate Start Fresh and Continuity pools. ENS also lists an existing-project integration prize; choose the applicable category only after the entrant's pool and prior work are confirmed.

The first priority is the actual card-to-Arc purchase. Graph must affect a real purchase decision. Do not add unrelated sponsor SDKs to fill application slots.

Separate ChatGPT Pro research was collected and checked against the [Circle CLI reference](https://developers.circle.com/agent-stack/circle-cli/command-reference) and [Graph Arc support](https://thegraph.com/docs/en/supported-networks/arc-testnet/). Circle's contract-execution CLI is a possible merchant sender, but its documented interface does not establish compatibility with this store's persisted signed-transaction recovery; testnet spending-policy limits are unavailable. Do not replace the working sender until recovery and gas caps can be retained. Graph supports Arc Testnet, but a purchase-history Subgraph must be built and deployed; [Studio setup](https://thegraph.com/docs/en/subgraphs/quick-start/) requires wallet connection and a deploy credential. Neither research nor network support is live integration evidence.

## What we are not claiming

The [World prize page](https://ethglobal.com/events/ethonline2026/prizes/world) describes AgentKit and Selfie Check integrations. Our private-policy ProveKit implementation is not evidence of either. Client-side ZK remains our core technical contribution, but it does not by itself establish eligibility for a World prize. We found no separately named ProveKit prize in the consulted [event prize listing](https://ethglobal.com/events/ethonline2026/prizes).

The Arc store, age contracts and sponsor are publicly deployed. Buyer checkout and Agent Stack integration remain unverified. Ledger and Chainlink are not current targets. No standalone Belkin prize was identified in the consulted listing.

## Decision before final submission

1. Confirm the actual event, pool and admissible pre-existing work using the entrant's dashboard and contribution history.
2. Implement and record Arc/Circle Agent Stack settlement and the real Privy flow. Keep its wallet and transaction evidence with the final commit.
3. Implement a meaningful Graph purchase decision using live data; retain a sanitized query/result and the resulting decision.
4. Include ENS only when its real Sepolia path and central product value are shown.
5. Draft sponsor feedback from actual integration experience, then choose only supported prizes in the submission form.

Until those gates pass, the interim report should say “proposed targets” and “live acceptance pending.” Missing integration evidence must not become a successful-looking UI or a fabricated transaction.
