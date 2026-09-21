# Arc USDC: read-only ERC-1271 compatibility evidence

Run `node scripts/probe-arc-usdc-1271.mjs` after installing the root lockfile.
The script uses only `eth_chainId`, `eth_getCode`, `eth_getBlockByNumber` and
`eth_call`, with two fixed [official Arc Testnet RPC endpoints](https://docs.arc.io/arc/references/connect-to-arc).
It never reads `.env`, wallet files or keys, signs, broadcasts, funds or deploys.

`eth_call` state overrides introduce an artificial ERC-1271 account, native USDC
balance and inspection harness for that call only. The USDC contract at
`0x3600000000000000000000000000000000000000` is the actual on-chain implementation
and is never overridden. The account accepts one exact digest and one public
96-byte signature sentinel. It is explicitly a test fixture, not a production
signature validator, age verifier or deployed Mate account.

## Observed on 2026-09-21

Both the primary and dRPC endpoints passed:

- A temporary 1 native USDC balance reads as 1,000,000 ERC-20 units.
- `transferWithAuthorization(..., bytes)` debits 250,000 units and credits the
  recipient exactly 250,000 units through a 96-byte ERC-1271 signature.
- `authorizationState` changes to used inside the same call, and immediate replay
  is rejected.
- Rejecting ERC-1271 code, a changed amount, recipient, nonce or signature, and
  insufficient balance all revert. Missing RPC/state-override support is an error,
  never a skipped success.

The [machine-readable result](evidence/arc-usdc-1271-2026-09-21.jsonl) records both
block hashes and the real token runtime hash. The state is discarded after each
call. There is **no transaction hash and no real purchase** from this test.

## What this does and does not unblock

The real token supports the bytes-signature / ERC-1271 path with a nonzero amount.
This removes one compatibility uncertainty for a future smart account. It does
not establish arbitrary facilitator compatibility, the deployed shop's support,
actual owner delegation or physical-iPhone acceptance.

ERC-1271 is a view validation hook: it cannot atomically update a shared spend or
purchase counter. SKU/age/region checks are also absent from the token's EIP-3009
message. A future policy settlement contract must bind the canonical quote and
proof, update its counters and move the token in one transaction. The existing
fixed-price account uses deterministic token nonces instead; it is not a general
catalogue/age-policy validator. Current public checkout remains the explicit
Privy EOA approval flow.
