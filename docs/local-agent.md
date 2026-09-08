# On-device task agent

Mate uses Apple's on-device Foundation Models for structured task extraction. `AgentPlanner` proposes translation or summary and copies the source text verbatim from the current message. Unknown operations and invented source text are rejected. It cannot choose a URL, sign transactions, change a budget or authorize itself. Ordinary conversation uses the existing conversation session.

The app owns the execution sequence: discover a real provider, obtain current mandate state, check its private policy, offer the exact text/provider/test-USDC price, and wait for an explicit answer. A fresh “yes” or “はい” is bound to that offer, draft and execution generation, expires after 60 seconds, and is discarded on rest/background/settings changes. One answer authorizes one request; this release does not grant blanket unattended purchasing permission.

After confirmation, the iPhone generates the ZK proof and signs the bound action through the existing restricted wallet. The API and merchant independently verify the proof; the result is accepted only after the phone checks the settlement evidence. The face stays open during this flow and the result is spoken instead of forcing the Activity screen open. If submission has an uncertain outcome, one automatic recovery attempt queries the existing action, or resubmits its exact persisted bytes when the server reports it missing. A still-pending request blocks new purchases.

This is a task-specific agent with a code-controlled execution sequence, not a general autonomous browser or a model that writes executable code. It still requires a funded approved mandate and live configured services. An unavailable connection is explained without pretending that an order ran. The current release asks for the exact quote's confirmation even when a mandate already exists; spoken budget amounts do not modify that signed mandate.

## Validation

- `make test` and `make build-ios` validate the existing core/server and app build.
- `AgentPlannerTests.testApprovalIsBoundToOneFreshOfferAndExplicitAnswer` checks expiry, explicit confirmation and binding to the exact draft/generation.
- Existing conversation lifecycle tests use a chat-only planner double to isolate cancellation behavior.
- `AgentPlannerTests.testRealLocalModelExtractsConcreteTaskWithoutInventingText` exercises Japanese/English requests, ordinary chat and unsupported shopping on the actual available Apple model. It must run on a supported physical device; a skipped test is not evidence of working task extraction.
- Full voice-to-settlement acceptance requires the physical phone, configured wallet/provider, actual client proof and confirmed testnet receipt. Simulator tests and local Anvil settlement tests do not establish that boundary.

Public implementation reference: [Apple guided generation](https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation). No model weights or extra model framework are bundled.
