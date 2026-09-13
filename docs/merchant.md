# Mate Atelier — merchant app

Run `npm run merchant`, then open `http://127.0.0.1:8790` on the Mac. The English-first shop console works even when payment integrations are not configured; it shows the shop as unavailable, never inserts sample orders, and never initiates a charge.

The first product is the existing real translation service (`PROVIDER_SERVICE=0`), or summary service (`1`). These are the two service permissions in the current `mate_policy` circuit. Physical goods, age credentials and shipping are not implemented by this app.

## Connect the shop

Use the existing provider environment configuration from `.env.example`: settlement RPC, vault, attestor address, recipient, price in six-decimal USDC units, Ollama model, provider API token and journal encryption key. Build the verifier and matching circuit resources with the repository's proof setup. `npm run merchant` starts the provider API on `PROVIDER_PORT` (8788 by default) and the read-only shop console on `MERCHANT_PORT` (8790). Stop any existing provider process first; the journal deliberately permits only one owner.

The console binds only to `127.0.0.1`. Enter `PROVIDER_API_TOKEN` in the operator form to see order metadata. It is kept in tab memory, never browser storage or a URL. Lock view clears it. Do not expose the operator console publicly. The provider API retains its installation-scoped bearer authentication and browser-origin rejection. For remote clients, use the existing HTTPS provider configuration and registration flow; the console itself is not a public checkout website.

Register this provider using the existing discovery setup (matching provider ID, recipient, price, service and HTTPS endpoint). The execution API must be updated with this release: `/v1/prepare` now carries the original client `proof` alongside its commitment. Old execution APIs that send only a proof hash cannot create new orders.

In Mate, review a translation request, choose the provider, approve a funded mandate and submit the explicitly approved text. Voice conversation alone does not dispatch purchases. No iPhone update is required for the new server-to-server proof forwarding.

## Order progression

1. The execution API checks the signed action and proof, then sends the same proof to the shop.
2. The shop checks the price, service, recipient, text hash, mandate state and agent signature. Its own ProveKit verifier checks the proof against the on-chain policy commitment and complete action hash (chain, vault, recipient, amount, request, expiry and nonce).
3. Only after verification does the shop run the real local model. A failed model call stays `verified`; retry must actually complete the work before returning `ready`.
4. The executor settles the payment. The shop independently checks the canonical vault event matching the action and proof hash before returning the result. It records `complete` only after that check.

The console shows the latest 50 persisted orders, proof commitments and payment transaction hashes. It excludes submitted text, output text, signatures, private policy values and raw proofs. Public order data includes price and commitments. The provider's encrypted journal retains the approved text and result for delivery/retry; raw proof bytes are transient at the merchant.

## Trust and limits

This is a testnet digital-service shop, not an Amazon purchasing integration or an age-verification system. The proof shows compliance with committed private spending rules; it does not establish real-world identity, age or private delivery. Prior spending and transaction details remain public. The vault trusts a server attestor rather than verifying ProveKit directly on-chain; the new merchant check is an additional independent verification before work begins.

`make test` covers rejected/missing proofs, altered commitments, model retry, payment gating and operator HTTP access using explicitly labeled unit doubles. These tests do not prove a live paid purchase. Live acceptance requires an actual iPhone proof, funded wallet, deployed vault, registered provider and confirmed testnet transaction; do not describe the shop as payment-verified until this has been exercised.
