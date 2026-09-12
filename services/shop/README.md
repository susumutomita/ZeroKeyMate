# Mate Atelier

Workers static assets + D1 + x402 v2, testnet only. The storefront currently
reports checkout unavailable. The repository now contains the signed-card age
circuit, a directly verifying EVM gate and the iPhone purchase integration. Public
deployment and the physical card-to-payment acceptance are still pending. See
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
authorization expires, both fixed providers must agree at a common finalized
block that the saved nonce is unused past its signed deadline before the order
can enter `payment_expired`. Otherwise it stays pending. The phone repeats that
check against its own saved authorization; absence of a receipt is insufficient.
The package test suite uses SQLite and injected network outcomes; it never
performs a real payment. The repository's separate `test-age-evm.mjs` executes
the actual proof and gate on a local chain with explicitly synthetic credentials.
Revocation is not checked. Private inputs do not belong in D1, Worker logs or UI.
# Age verification RPC trust

The Worker calls the pinned `MateAgeGate` bytecode through two separately
operated Base Sepolia providers: Base (`sepolia.base.org`) and Allnodes/PublicNode
(`base-sepolia-rpc.publicnode.com`). Both must agree on the same recent block
hash, timestamp, chain, bytecode hash and contract result before age acceptance,
and the check repeats immediately before settlement. Disagreement or failure
keeps checkout locked. A single fabricated approval is insufficient.

This is a 2-of-2 RPC trust assumption, **not** a light-client proof of execution.
Collusion/compromise of both providers can fabricate the result. Both receive
only the public order-bound proof and inputs. The x402 USDC authorization does
not itself execute the age gate; merchant fulfillment depends on this Worker
boundary. Do not describe this as trustless or an on-chain age transaction.


## Prepare the matching public contracts without credentials

From the repository root, after the reviewed native setup is built:

```sh
python3 scripts/prepare-age-deployment.py --out .build/age-deployment
```

This checks the reviewed circuit record, masking patch and full public prover /
verifier hashes. It exports Solidity anew from the pinned verifier key, checks
the upstream template patch and compiles only the actual verifier and government-
root age gate. It writes an unsigned package into a new directory and refuses
to overwrite one. It does not use `.env`, credentials, a wallet, network access
or deployment. The package includes ABI, creation bytecode, runtime templates,
compiler settings, immutable locations and source/setup hashes. The gate runtime
hash depends on its verifier address; the zero-filled template hash is **not**
the deployed gate hash. No synthetic root or test token is included.

`config/age-deployment-pins.json` independently pins the **entire** deterministic
package, including both creation/runtime bytecodes, ABI and immutable positions.
Both preparation and loading refuse a different digest; copied setup pins and
self-consistent bytecode hashes cannot authorize substitute contracts. Changing
the compiler, sources or public setup requires reviewing the regenerated
contracts and this repository pin. Never accept a digest supplied alongside an
untrusted deployment package, or update the pin merely to silence a mismatch.

After explicitly authorized testnet deployment, stage the phone connection with
public coordinates and that exact package:

```sh
node scripts/stage-shop-connection.mjs \
  --deployment-package .build/age-deployment \
  --origin https://YOUR-SHOP.workers.dev \
  --recipient 0xYOUR_TESTNET_RECIPIENT \
  --verifier 0xDEPLOYED_VERIFIER \
  --age-gate 0xDEPLOYED_AGE_GATE
```

The staging command checks the package against the phone's setup pins, fills the
compiler-reported gate immutables, then checks **both** complete deployed runtime
bytecodes through the two fixed RPC providers at one common recent block. It
writes the derived gate hash into the public phone configuration only when all
checks agree. It performs no order, signature or payment and never overwrites an
existing connection. Apply the same gate address/hash and recipient to Workers
public configuration, provide the authorized D1 binding, migrate and verify live
readiness before installing the configured app. Account access and testnet
wallet authorization remain separate user actions.

## Reproduce the synthetic local integration

On a host with the native age FFI, public setup, Python cryptography, Anvil and
both npm dependency sets installed:

```sh
node scripts/test-shop-native-e2e.mjs --deployment-package .build/age-deployment
```

The test creates fresh RSA and EVM keys in memory, uses a generated synthetic
card certificate bound to a real shop-created order, runs the actual native ZK
prover and Solidity verifier, then exercises x402 headers, a real EIP-712
signature, local EVM transfer, SQLite persistence and restart/retry recovery.
It also checks the prepared deployed runtimes and rejects mismatched addresses,
a changed RPC bytecode response and use of the same client twice. Each run writes
an ignored `.build/shop-integration-*/acceptance.json` report.

The official government-root gate must reject the synthetic card. Positive age
acceptance uses an explicitly test-only subclass with a fresh synthetic root.
The token and settlement adapter are test-only, two clients share the same local
node, and SQLite substitutes for deployed D1. This does **not** verify a physical
card, Circle USDC, the public facilitator, independent RPC operators, Cloudflare
hosting or the complete iPhone UI. None of these test substitutes is shipped.
