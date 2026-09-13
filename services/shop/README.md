# Mate Atelier

Workers static assets + D1 + a sponsor Durable Object + x402 v2, testnet only. The storefront currently
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

Public configuration is in `wrangler.jsonc`: only chain 5042002 is accepted, and the
gate address, pinned runtime code hash and payment recipient must all be present.
These fields are not wallet private keys. Readiness checks the chain ID, a recent
block, pinned gate code, rejection of an empty order, D1 table/capacity and the
store's explicitly configured Arc settlement wallet, gas balance and fee cap. Outages reject new orders while leaving
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
stores only its hash in D1. The separate sponsor Durable Object journals the
exact signed public USDC transaction before broadcast, as described below. GET only reconciles and never submits a payment. If the
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
operated Arc Testnet providers: the primary Arc endpoint (`rpc.testnet.arc.io`)
and dRPC (`rpc.drpc.testnet.arc.io`). Both must agree on the same recent block
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
signature, local EVM transfer, SQLite persistence and restart/retry recovery, including a lost first
submission resumed from saved transaction bytes by the production queue alarm.
It also checks the prepared deployed runtimes and rejects mismatched addresses,
a changed RPC bytecode response and use of the same client twice. Each run writes
an ignored `.build/shop-integration-*/acceptance.json` report.

The official government-root gate must reject the synthetic card. Positive age
acceptance uses an explicitly test-only subclass with a fresh synthetic root.
The token is test-only. Settlement uses the actual product adapter with a fresh
local sponsor key; two clients share the same standard Anvil node, and SQLite
substitutes for deployed D1. Standard Anvil does not reproduce Arc native-USDC
precompile semantics. This does **not** verify a physical
card, Circle USDC settlement, independent RPC operators, Cloudflare
hosting or the complete iPhone UI. No synthetic token, root or test wallet is shipped.

## Arc settlement and credential boundary

The shop self-facilitates x402 v2 `exact` EIP-3009 payments. The former
`x402.org/facilitator` supports Base Sepolia but did not advertise Arc at the
2026-09-13 check. An Arcon URL found in public research did not resolve. Neither
is used as a fallback. Circle Gateway nanopayments use a different signing
domain and settlement model; they are not interchangeable with this direct
USDC transfer.

`ARC_SETTLER_ADDRESS` is public configuration. `ARC_SETTLER_KEY` must be a
**new, separately approved, testnet-only** Worker secret whose derived address
matches it. Never use an existing personal wallet key. No key is bundled,
generated, read from disk, or uploaded by building/testing this code. Live
configuration and funding require explicit owner approval. The buyer signs through the iPhone's Privy embedded-wallet SDK; the Worker sees
only the exact signed 0.10 USDC authorization and never the buyer key. This does
not claim that the wallet's authentication/signing works entirely offline.

The sponsor can submit only `transferWithAuthorization` to Arc's official USDC
address, with the configured merchant receiving exactly 100,000 atomic units
(0.10 USDC, ERC-20 six decimals). It validates the signature independently,
simulates the real USDC call, and rejects a wrong chain, amount, receiver,
domain, expired authorization or fee above the cap. Native gas uses **18**
decimals: 150,000 gas at 25 gwei caps each submitted attempt at **0.00375 test
USDC**. Its funding balance bounds aggregate exposure. Never fund this key with
real assets on any network. No unrestricted facilitator endpoint is exposed.

`ARC_SETTLEMENT` routes all payments for one sponsor address to the same
SQLite-backed Durable Object. It serializes nonce allocation across Worker
instances, waits for both providers to confirm the previous sponsor nonce is
finalized, and refuses an unknown pending transaction or nonce disagreement.
Do not use the dedicated sponsor wallet outside this queue.

Before broadcast it atomically saves the exact signed transaction and a retry
alarm. A lost response, process restart or alarm can only rebroadcast those same
bytes, never replace the nonce, extend the buyer's deadline, or raise the gas fee.
The alarm checks again every minute until the sponsor nonce is finalized; an
expired authorization can only revert, not transfer funds. The final record
retains the transaction hash/payer/nonce and removes the raw signed bytes. Records
are capped at 1,000, matching the shop's bounded order capacity. These are public
payment data, not card inputs or private keys. No payment HTTP header is stored
in D1. Purchase completion still requires the exact successful receipt evidence;
sponsor nonce consumption alone can also mean a reverted transaction.

A submitted transaction is not a completed order. The Worker and phone require
matching receipt evidence from both fixed providers. Only ERC-20 logs emitted
by `0x3600000000000000000000000000000000000000` count; Arc's separate native
18-decimal system-emitter logs must not be counted as an extra purchase.

Arc uses a new Worker/D1 name and phone storage namespace. Old Base order state
is not migrated, discarded, or interpreted as an Arc authorization. The
experimental prover parameters and verifier stay unchanged; the gate's chain
allowlist and the reviewed whole-package digest are updated for Arc.

Arc deployment is relevant to the Arc/USDC payments prize. This checkout alone
**does not claim Circle Agent Stack integration**. The separate API's Circle
attestor adapter is not part of this age-checkout path. An Agent Stack prize
submission still needs a meaningful, live, separately authorized integration,
plus the current prize's frontend/backend, diagram, video and documentation.
See the source review in `docs/arc-checkout.md`.
