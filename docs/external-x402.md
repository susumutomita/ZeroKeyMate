# Connected x402 services

The native app now exposes **Connected services** in Settings and controls.
Add an HTTPS resource, review its recipient and maximum charge, and give it a
name. Say “use Weather” or “天気を使って” for a service registered under that name.
This opens a fresh quote; a spoken request does not authorize a transfer.
The dedicated beer/water shop remains a separate age-aware protocol.

## Supported profile and approval

This is an opt-in **Arc Testnet** client for x402 v2 `exact`, HTTPS GET without a
body, USDC `0x3600000000000000000000000000000000000000`, EIP-3009, and the
USDC/version-2 EIP-712 domain. The maximum per request is 0.50 test USDC. It is
not a general web browser, mainnet wallet, or full x402 implementation. Other
networks, assets, Permit2, unknown extras and nonempty extensions are rejected.
Registration requires exactly one matching offer and explicit review of the
resource, recipient and ceiling. Discovery cannot transmit a signature.

Each purchase gets a fresh quote, two-provider balance preflight, exact payment
review, device-owner authentication (Face ID/passcode), and a Privy buyer-wallet
signature. Insufficient funds are reported before signing with a buyer-address
share action and Circle faucet link. The transfer still can fail if the balance
changes afterward. The LLM never receives signing or approval capabilities.

`PaymentSignatureVerifier` independently recovers the EIP-712 signer on the
phone using pinned libsecp256k1 and Keccak-256. It requires the exact payer,
recipient, amount, token, chain, nonce and signed deadline, with canonical low-S
ECDSA signatures. A 65-byte string alone is not verification. Sources, versions
and licenses are in [SOURCES.md](SOURCES.md) and the bundled notices.
MynaWallet, contract-wallet signatures and delegated purchases are not enabled
by this EOA adapter.

An EIP-3009 signature binds the transfer, **not HTTP resource, SKU, delivery or
age eligibility**. Registration and exact-origin checks are client checks, not
on-chain product permissions. The experimental [catalogue budget](catalogue-budget.md)
uses a separate product-aware, atomic protocol. It is not interchangeable with
bare EIP-3009.

## Interruption, retries and completion

One device-only Keychain journal serializes approval, signing and transmission.
It is written before invoking each side effect. A denied unsigned approval can
be canceled; an interrupted signing attempt remains unresolved. No extension
or other process may write this single-process journal. Unreadable or unknown
state blocks a new payment; old bare signed records and version-1 records migrate
without being discarded.

A timeout, cancellation, backgrounding, process restart, malformed response or
HTTP failure preserves the original payment. Retry reuses its exact nonce,
signature and deadline. It does not ask for a new signature. A fresh approval
expires after at most 180 seconds; signing preserves the original advertised
settlement window, including time spent in device authentication.

Both settlement and service response are recorded separately. A 200 response
alone is not a confirmed payment. A confirmed transfer with no 2xx result is
shown as **Payment confirmed · Result unavailable**. Response content is bounded
and displayed as plain text, never executed or passed to the model as an
instruction. A completed history item contains no reusable signature.

A matching transaction from a merchant header or manually entered hash is only
a locator. If the header is missing, the client searches the most recent 1,000
finalized blocks for the token's exact payer/nonce event, then fully verifies the
receipt. Older missing receipts may need a manual transaction hash. A used nonce
alone never establishes a matching transfer or delivered result.

Only these terminal outcomes release an entry:

- A corroborated successful transfer moves the original payment and its bounded
  response into local history, then atomically clears the pending entry.
- **Check expired authorization** queries the exact token nonce at the same
  finalized block hash through both fixed RPC endpoints using EIP-1898. The
  block timestamp must be at or beyond `validBefore`, and both calls must return
  the canonical 32-byte false value. The finalized block/heads are reread to
  detect contradictions. This releases a signed or interrupted-signing entry
  only when the token can no longer use it. Elapsed phone time never suffices.

Late cleanup cannot clear a newer payment. Recent completed/expired nonces are
retained to reject reuse. On-chain nonce enforcement is the lasting replay
boundary. Retrying the same authorization prevents another token transfer;
**it cannot guarantee idempotent HTTP fulfillment** by an arbitrary merchant.

## RPC and transport trust

The client pins `https://rpc.testnet.arc.io` and
`https://rpc.drpc.testnet.arc.io`. Both must report Arc Testnet and agree on a
common finalized checkpoint and the successful canonical receipt. Block position,
timestamp, token, log metadata, payer, recipient, amount and nonce are checked.
The AuthorizationUsed event must be followed by the expected Transfer in the
token event stream. Changed heads, malformed, missing, contradictory and
unavailable responses stay unresolved.

These URLs may share infrastructure. This is RPC corroboration, not a
cryptographic receipt-inclusion proof or a claim of independently operated nodes.
On September 22, 2026 a read-only check confirmed EIP-1898 canonical block-hash
calls on both endpoints at block 63349652, hash
`0x121dc9fee89093e3279ab13c6a4736099f4f71f9695b95c877ce661700ab42ce`.
That used a synthetic public address/nonce, not a payment or private key.

The HTTP clients disable cookies, shared credentials and caches, reject redirects,
and bound merchant bodies to 64 KiB and RPC replies to 1 MiB. Receipt logs are
limited to 256 and block transactions to 8,192. Legitimate oversized responses
therefore remain unresolved. URL checks reject credentials, local literal IPs,
queries and normalization ambiguity; they do not claim DNS rebinding isolation.
Only add services you intend to contact.

## Validation and remaining acceptance

Core tests cover wire/domain/amount tampering, discovery ambiguity, viem-derived
real ECDSA vectors, signature malleability, concurrent approvals, every journal
write boundary, cancellation, migration, late cleanup and terminal transitions.
Native transport tests cover discovery capability separation, fixed endpoint
binding, response bounds, restart retries, canonical settlement, missing-locator
recovery, expired-unused reconciliation and balance checks. UI tests exercise
registration entry, decimal keyboard dismissal and closing without payment.
Synthetic fixtures never use the user's wallet, keys, card or PIN.

Physical owner approval and purchases through two independently operated
external services still require acceptance. Controlled tests do not establish
those outcomes. The service must implement this exact Arc/USDC profile and its
own result-recovery semantics. Registration cannot make an unsupported endpoint
compatible. Do not describe this as “any site” or production financial assurance.

Primary sources: [x402 v2](https://github.com/x402-foundation/x402/blob/6323ec74c85607e706e0722dd294365a7fb57768/specs/x402-specification-v2.md),
[exact EVM](https://github.com/x402-foundation/x402/blob/6323ec74c85607e706e0722dd294365a7fb57768/specs/schemes/exact/scheme_exact_evm.md),
[ERC-3009](https://eips.ethereum.org/EIPS/eip-3009),
[Circle's token implementation](https://github.com/circlefin/stablecoin-evm/blob/master/contracts/v2/EIP3009.sol),
[Arc finality](https://docs.arc.io/integrate/infrastructure/indexing-events),
[dRPC infrastructure disclosure](https://blog.drpc.org/blog-arc-rpc-endpoint-live-on-nodecloud/).
