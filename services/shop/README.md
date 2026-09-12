# Mate Atelier

Workers static assets + D1 + x402 v2, testnet only. The storefront currently
reports checkout unavailable. This package does not contain the age circuit,
deployed gate or iPhone purchase integration. See
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
These fields are not wallet private keys. Current readiness means configuration
presence, so it must be strengthened before enabling public checkout.

The native client generates a cryptographically random 32-byte request capability
and sends its lowercase hex form as `X-Order-Key` on every request. Do not put the
capability into a URL or logs. Keep it with the pending order on the phone.

- `GET /api/catalog`: product and configuration status.
- `POST /api/orders`: `{productId: "mate-lager", quantity: 1, payer: "0x…"}`.
- `GET /api/orders/{id}`: retrieve/reconcile this order.
- `POST /api/orders/{id}/age`: query the proposed on-chain age gate. This is not
  proof submission yet; no DOB, card certificate, PIN or raw card signature belongs
  in this endpoint.
- `POST /api/orders/{id}/pay`: returns actual x402 v2 requirements in
  `PAYMENT-REQUIRED`. A subsequent `PAYMENT-SIGNATURE` must authorize the original
  order's nonce, payer, recipient, token, amount, chain and time window.

A timeout returns `payment_pending`, never permission to generate a second
authorization. The payment hash can be recovered from the original nonce's USDC
event. Definitive failure/cancellation recovery is still pending implementation.
The test suite uses SQLite and injected network outcomes; it never performs a
real payment. Private inputs do not belong in D1, Worker logs or the shop UI.
