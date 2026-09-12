# Mate Atelier

Workers static assets + D1 + x402 v2, testnet only. The storefront currently
reports checkout unavailable. The repository now contains the signed-card age
circuit and a directly verifying EVM gate, but no public deployment or iPhone
purchase integration. See
[the implementation checkpoint](../../docs/age-shop-progress.md).

## Local development

Use Node 22.13 or newer. This package does not require `.env` or a wallet key.

```sh
npm ci --ignore-scripts
npm test
npm run types
npm run build
npm run dev -- --local
```

The page is at http://localhost:8791/ . `build` is a dry run. To migrate only the
local D1 database, use `npx wrangler d1 migrations apply ORDERS --local`. Do not
remove `--local` without reviewing the destination. Do not deploy before the
gate/prover/payer flow and Cloudflare authorization are ready.

Public configuration is in `wrangler.jsonc`: only chain 84532 is accepted, and the
gate address, pinned runtime code hash and payment recipient must all be present.
These fields are not wallet private keys. Readiness checks the chain ID, a recent
block, pinned gate code, rejection of an empty order, D1 table/capacity and the
facilitator's x402 v2 Base Sepolia support. Outages reject new orders while leaving
existing order retrieval available. This probe is not a substitute for a real
proof/payment acceptance run.

Two Workers rate-limit bindings cap API requests and new orders per Cloudflare
location. Their namespace IDs must be unused in the target account before
deployment. They use fixed resource keys, not IP addresses. These approximate
limits are not payment accounting. D1 separately caps this test shop at 1,000
orders atomically; reaching capacity requires operator review, not automatic
deletion of pending payments.

The native client generates a cryptographically random 32-byte request capability
and sends its lowercase hex form as `X-Order-Key` on every request. Do not put the
capability into a URL or logs. Keep it with the pending order on the phone.

- `GET /api/catalog`: product and live readiness status.
- `POST /api/orders`: `{productId: "mate-lager", quantity: 1, payer: "0x…"}`.
- `GET /api/orders/{id}`: retrieve/reconcile this order.
- `POST /api/orders/{id}/age`: `{proof: "0x…", rootKeyHash: "0x…"}`. The proof is
  exactly 384 bytes from the age Groth16 backend. The Worker constructs all eight
  public inputs from this order and asks `MateAgeGate.verifyOrderAge` via
  `eth_call`. It stores the public proof only after successful contract checking,
  and checks it again before payment. No age transaction, signer or attestor is
  used. DOB, card certificate, PIN, raw card signature and caller-supplied public
  inputs are rejected; they do not belong in this endpoint.
- `POST /api/orders/{id}/pay`: returns actual x402 v2 requirements in
  `PAYMENT-REQUIRED`. A subsequent `PAYMENT-SIGNATURE` must authorize the original
  order's nonce, payer, recipient, token, amount, chain and time window.

A timeout returns `payment_pending`, never permission to generate a second
authorization. The payment hash can be recovered from the original nonce's USDC
event. After one minute, a client can resubmit the **exact original**
`PAYMENT-SIGNATURE` to `/pay`. The server rechecks age approval and reserves a new
attempt atomically; it never issues a replacement payment challenge, nonce or
longer validity. Keep that header securely on the phone while pending; the Worker
stores only its hash. GET only reconciles and never submits a payment. If the
authorization has expired without a confirmed outcome, keep checking the order;
terminal failure/cancellation recovery still needs implementation.
The package test suite uses SQLite and injected network outcomes; it never
performs a real payment. The repository's separate `test-age-evm.mjs` executes
the actual proof and gate on a local chain with explicitly synthetic credentials.
Revocation is not checked. Private inputs do not belong in D1, Worker logs or UI.
