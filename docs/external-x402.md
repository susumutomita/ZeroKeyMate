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
180 seconds for **new approval**. Signing within that period gives the
authorization its full advertised `maxTimeoutSeconds` settlement window, as in
the reference EIP-3009 client. A retry uses that original signed deadline even
if the quote's approval deadline has since passed; it never extends either one.
`PaymentAuthorization` binds the corresponding transfer fields;
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

This gate rejects a second signature's **reservation and transmission**. It does
not yet prevent the signature from being generated: no signing provider is
connected. That provider must serialize/preflight approvals before Face ID and
signing, then still use the atomic journal gate before transmission. The current
65-byte check is structural; the future provider must recover the EIP-712 signer
and match the approved payer locally before persisting the signature.

`PaymentReceipt` is only a server settlement claim. Both reported success and
`settlement_pending` can supply a transaction for reconciliation outside the
merchant HTTP channel. `validateTransfer` requires the expected USDC
AuthorizationUsed followed by the matching Transfer in the token's event stream,
with no duplicate use or cancellation of that nonce. This follows Circle's
EIP-3009 event ordering and cannot combine unrelated transfers in a batch.
Its caller must first establish the exact
transaction hash, correct chain, successful status, canonical block and
confirmation through trusted RPCs. The presence of a server header
or `authorizationState == true` alone does not establish a successful transfer.
HTTP status and settlement are separate observations: a failing HTTP response
can arrive after a real transfer. A receipt claim on that response may be used
for reconciliation, never to claim successful resource delivery. Conversely a
200 response without verified settlement does not establish a paid purchase.

`ExternalPaymentReconciliation` implements that read-only check. It pins
`https://rpc.testnet.arc.io` and `https://rpc.drpc.testnet.arc.io`; neither the
merchant nor the model can supply an RPC URL. Both must report Arc Testnet and
agree on the smaller finalized height's block hash, number, timestamp and
transaction list. Both receipts must agree, report success, and refer to the
same canonical block at or below that checkpoint. The transaction must occupy
its claimed index in that block. Log metadata, ordering, token, payer, recipient,
amount and nonce are checked; the block must fall within the signed time window.
The checkpoint is bound to the initially reported finalized block. The common
checkpoint and both finalized heads are reread before returning evidence;
regression, replacement or conflicting equal-height heads are rejected. Malformed, missing,
reverted, oversized, redirected or contradictory results remain **unresolved**.

The RPC transport is bounded to 1 MiB per response, 256 receipt logs and 8,192
block transactions, with no cookies, shared credentials, additional caller
headers, redirects or write RPC methods. An oversized legitimate block can
therefore leave this intentionally restricted client unresolved.
`ExternalPaymentRecovery.reconcile` reads the original journal entry and returns
only the evidence; it never changes the signature, clears the journal or marks
the resource delivered. A settled payment remains settled after its deadline.
Cancellation propagates without becoming an unpaid result.

**Trust boundary:** two URLs are not proof of two independent operators. dRPC
states that its infrastructure powers Arc public endpoints. This is a
two-endpoint consistency check with an RPC trust assumption, not light-client
verification or a cryptographic receipt-inclusion proof. Arc provides
deterministic finality; this implementation still requires both endpoints to
support `finalized` and fails closed on errors. It does not use `eth_call`,
`authorizationState` or rely on unconfirmed EIP-1898 support. A separately
operated node/provider and its trust policy remain release work.

## Not yet connected

- Native service registration/review and exact-payment approval UX.
- A `PaymentProvider` that checks the approved snapshot again around Face ID
  and signing; the model must never receive this provider.
- User-facing reconciliation, transaction discovery when the server supplies no
  locator, and a carefully checked journal-release path. The current journal
  deliberately has no delete/reset convenience API.
- Recovery of resource delivery after settlement: a service may reject a used
  nonce instead of returning the original result. Identical authorization
  prevents a second transfer, **not** guaranteed idempotent HTTP fulfillment.
- Two independent services' actual Arc/USDC/facilitator support and physical
  iPhone tests for completion, cancellation, timeout and restart.

Do not connect this infrastructure to a purchase button until those paths are
implemented and tested. In particular, a deadline passing does not authorize
a replacement payment: the original could already have settled. A new signature
requires chain reconciliation, an explicit new approval and service-level
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
Reconciliation tests additionally cover provider lag, checkpoint changes,
receipt/chain disagreement, missing transactions, cancellation, removed or
misbound logs, expired-but-settled payments, response limits and retained journals.
Those are controlled tests, not an external purchase or financial audit.

The implementation is independent Swift code based on the official public
[x402 v2 specification](https://github.com/x402-foundation/x402/blob/6323ec74c85607e706e0722dd294365a7fb57768/specs/x402-specification-v2.md)
and [exact EVM scheme](https://github.com/x402-foundation/x402/blob/6323ec74c85607e706e0722dd294365a7fb57768/specs/schemes/exact/scheme_exact_evm.md),
reviewed September 21, 2026. No new third-party runtime dependency is added.

Additional primary sources: [ERC-3009](https://eips.ethereum.org/EIPS/eip-3009),
[Circle's public implementation](https://github.com/circlefin/stablecoin-evm/blob/master/contracts/v2/EIP3009.sol),
[Arc finality and event semantics](https://docs.arc.io/integrate/infrastructure/indexing-events),
and [dRPC's public endpoint infrastructure disclosure](https://blog.drpc.org/blog-arc-rpc-endpoint-live-on-nodecloud/).
