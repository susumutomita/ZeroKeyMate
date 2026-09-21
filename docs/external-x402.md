# External x402 client boundary

This is **pre-Tokyo development infrastructure, not an enabled purchase flow**.
The existing two-product shop still uses its dedicated order protocol and
explicit owner approval. No external endpoint, new signing method, wallet
permission, payment or age check is enabled by these types.

## Implemented

`PaymentService` is an application-reviewed HTTPS GET endpoint with a fixed
recipient and a ceiling of at most 0.50 test USDC. The response and local model
cannot change it. The initial profile accepts x402 v2 `exact`, Arc Testnet
`eip155:5042002`, USDC `0x3600000000000000000000000000000000000000`, and the
USDC/version-2 EIP-712 domain. Alternate assets, networks, payment flows and
Permit2 are unsupported. Exactly one advertised option must match the profile.
Unknown extra fields and nonempty challenge extensions are rejected. This is
a deliberately narrow interoperability profile, not full x402 conformance.

`PaymentRequest` validates the challenge's exact resource, recipient, canonical
integer amount, timeout and domain metadata. It expires locally after at most
180 seconds. `PaymentAuthorization` binds the corresponding transfer fields;
`PendingPayment` serializes the selected requirement and authorization without
changing the nonce, deadline or signature on retry. Restored data is revalidated.

`ExternalPaymentClient` disables cookies, shared credentials and caches, rejects
redirects, sends only GET without a body, and caps response bodies at 64 KiB.
It never fetches a URL, icon, instruction or redirect supplied in a challenge.
Registration is trusted application configuration; these URL checks alone do
not claim to prevent DNS rebinding for an untrusted dynamically added service.

`ExternalPaymentRecovery` atomically reserves one unresolved payment in a shared
device-only Keychain journal **before** transmitting it. Another coordinator
cannot replace it. A timeout, cancellation, restart, malformed response or
elapsed authorization deadline does not delete that entry. Identical retries
use the same payment header; a different payment remains blocked. A failure to
persist prevents transmission. Tests use an in-memory journal and synthetic
signatures, not the device's wallet or existing Keychain entries.

`PaymentReceipt` is only a server settlement claim. Both reported success and
`settlement_pending` can supply a transaction for independent reconciliation.
`validateTransfer` requires the expected USDC Transfer and AuthorizationUsed
events in the same transaction. Its caller must first establish the exact
transaction hash, correct chain, successful status, canonical block and
confirmation through trusted independent RPCs. The presence of a server header
or `authorizationState == true` alone does not establish a successful transfer.

## Not yet connected

- Native service registration/review and exact-payment approval UX.
- A `PaymentProvider` that checks the approved snapshot again around Face ID
  and signing; the model must never receive this provider.
- Independent chain reconciliation and a carefully checked journal-release
  path. The current journal deliberately has no delete/reset convenience API.
- Recovery of resource delivery after settlement: a service may reject a used
  nonce instead of returning the original result. Identical authorization
  prevents a second transfer, **not** guaranteed idempotent HTTP fulfillment.
- Two independent services' actual Arc/USDC/facilitator support and physical
  iPhone tests for completion, cancellation, timeout and restart.

Do not connect this infrastructure to a purchase button until those paths are
implemented and tested. In particular, a deadline passing does not authorize
a replacement payment: the original could already have settled. A new signature
requires independent reconciliation, an explicit new approval and service-level
duplicate-fulfillment handling.

Ordinary EIP-3009 authorizes payer, recipient, amount, nonce and time window in
the token/chain domain. It **does not cryptographically bind HTTP resource, SKU,
delivery or age eligibility**. Client-side origin checks do not turn it into an
on-chain product permission. The experimental atomic catalogue budget uses a
different order-aware enforcement path; see [catalogue-budget.md](catalogue-budget.md).

## Validation and sources

Core tests cover wire encoding, domain/network/token/recipient/price tampering,
ambiguous offers, unsupported extensions, invalid URLs, expiry, corrupted saved
data, exact retry bytes and separate transfer/authorization evidence. iOS
URLProtocol tests cover cookie/credential exclusion, redirects, body bounds,
timeout/restart retry, storage failure and concurrent journal reservation.
Those are controlled tests, not an external purchase or financial audit.

The implementation is independent Swift code based on the official public
[x402 v2 specification](https://github.com/x402-foundation/x402/blob/6323ec74c85607e706e0722dd294365a7fb57768/specs/x402-specification-v2.md)
and [exact EVM scheme](https://github.com/x402-foundation/x402/blob/6323ec74c85607e706e0722dd294365a7fb57768/specs/schemes/exact/scheme_exact_evm.md),
reviewed September 21, 2026. No new third-party runtime dependency is added.
