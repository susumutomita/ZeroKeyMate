# On-device task agent

Mate uses Apple's on-device Foundation Models for structured task extraction. `AgentPlanner` proposes translation or summary and copies the source text verbatim from the current message. Unknown operations and invented source text are rejected. It cannot choose a URL, sign transactions, change a budget or authorize itself. Ordinary conversation uses the existing conversation session.

The app owns the execution sequence: discover a real provider, obtain current mandate state, check its private policy, offer the exact text/provider/test-USDC price, and wait for an explicit answer. A fresh “yes” or “はい” is bound to that offer, draft and execution generation, expires after 60 seconds, and is discarded on rest/background/settings changes. One answer authorizes one request. Alternatively, after choosing a real provider, **Authorize this shop and limit** uses device-owner authentication to store consent for that service, provider ID, recipient, per-request price, chain, vault and current mandate only. Subsequent direct translation/summary commands may run without a repeated quote confirmation, while the signed policy still enforces total spending. New prices above the cap, replacement mandates, changed recipients and other services fall back to confirmation. The model cannot create this standing permission.

After confirmation, the iPhone generates the ZK proof and signs the bound action through the existing restricted wallet. The API and merchant independently verify the proof; the result is accepted only after the phone checks the settlement evidence. The face stays open during this flow and the result is spoken instead of forcing the Activity screen open. If submission has an uncertain outcome, one automatic recovery attempt queries the existing action, or resubmits its exact persisted bytes when the server reports it missing. A still-pending request blocks new purchases.

This is a task-specific agent with a code-controlled execution sequence, not a general autonomous browser or a model that writes executable code. It still requires a funded approved mandate and live configured services. An unavailable connection is explained without pretending that an order ran. Without explicit shop delegation, each new request still needs the exact quote's confirmation. Spoken budget amounts do not modify the signed mandate. A deterministic direct-instruction check outside the source text rejects questions, negation and quoted commands from unattended execution. Ambiguous phrasing can still propose a quote, but never silently authorizes it. **Controls → Stop automatic orders** revokes local permission and invalidates a pending signature/retry; already submitted transactions remain subject to receipt recovery. A persisted disable preference prevents a failed Keychain deletion from re-enabling consent on restart.

## Validation

- `make test` and `make build-ios` validate the existing core/server and app build.
- `AgentPlannerTests.testApprovalIsBoundToOneFreshOfferAndExplicitAnswer` checks expiry, explicit confirmation and binding to the exact draft/generation.
- Existing conversation lifecycle tests use a chat-only planner double to isolate cancellation behavior.
- `AgentPlannerTests.testRealLocalModelExtractsConcreteTaskWithoutInventingText` exercises Japanese/English requests, ordinary chat and unsupported shopping on the actual available Apple model. It must run on a supported physical device; a skipped test is not evidence of working task extraction.
- Full voice-to-settlement acceptance requires the physical phone, configured wallet/provider, actual client proof and confirmed testnet receipt. Simulator tests and local Anvil settlement tests do not establish that boundary.

Public implementation reference: [Apple guided generation](https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation). No model weights or extra model framework are bundled.

Mac-host acceptance on 2026-09-08 ran the same planner source with the actual Apple model: Japanese/English translation commands extracted their exact text, while greetings and Amazon purchases produced no task. This is host evidence, not a physical-iPhone acceptance result.

Say “注文を確認して” or “Check my order” to recover the persisted pending order from the conversation. This uses the same action and saved submission, never a newly created order. If no order is pending, Mate says so instead of inventing a result.
