# Atomic catalogue budget — local research

`MateCatalogBudget` connects canonical product rules, merchant and agent
signatures, age-proof verification, shared spending/count limits and token
transfer in one transaction. It is **local-chain only (31337), not deployed,
funded or enabled in the iPhone shop**. It is pre-Tokyo work. Current public
x402 checkout still requests the owner's explicit approval of each payment.

## Enforced terms

The owner's deployment fixes a token, code-hash-pinned age gate, up to 16 agent
keys and 16 merchants, allowed products, per-purchase/total limits, purchase
count (up to 100) and expiry (up to one day). None can be widened or reset.
Catalogue v1 has beer at 100,000 token units with age 20, and water at 50,000
units with no age requirement. One order contains one to five bottles of one
SKU. The count counts **orders**, not bottles. Prices use the existing shop's
six-decimal unit convention; arbitrary tokens/currencies are not supported.

An allowed merchant signs a quote; an allowed agent independently signs the
same order. Both EIP-712 domains bind the chain and this budget. The contract
recomputes the `ZKM-AGE-ORDER-1` commitment, binding gate, SKU, quantity, this
budget as payer, merchant, token, canonical amount, expiry and payment nonce.
There is no caller-supplied price or minimum age. Unknown/forbidden items and
merchants are rejected.

For beer, the pinned gate must verify the actual order-bound age proof inside
the transaction. Water rejects unexpected proof material. Global order IDs and
nonces prevent replay across agents. The spent/count/used markers and exact
token transfer succeed or roll back together. Extra funding never replenishes
authorization. There is no generic execution, allowance or ERC-1271 fallback.

Agent and merchant address sets must be disjoint, preventing a configuration
that lets the same address sign both sides. This cannot prove that distinct
addresses belong to independent people; the owner still chooses trusted roles.

Only the owner can stop every agent or withdraw back to the owner; withdrawal
also stops the budget. Revocation is effective when mined. This is a personal
allowance, **not a campaign allocation with locked withdrawals**. A merchant
signature confirms the quoted terms, not physical delivery.

## Reproduce

```sh
make test-contracts
python3 scripts/build-age-evm.py
node scripts/test-catalog-age.mjs .build/age-proof-engine/artifacts
```

The first command includes the eleven catalogue-policy tests: canonical pricing,
cross-agent replay, excess-funded count and budget caps, same-block competing
purchases, disallowed products/merchants, signature/quote/domain tampering,
failed age checks, mined failed-transfer rollback, callback reentrancy, owner stop/withdrawal and expiry.
Its rejection-only verifier cannot fabricate a passing age proof.

The cryptographic acceptance command goes further. It creates a fresh synthetic
issuer and card entirely in memory, signs the actual local order challenge,
generates a **real Groth16 proof with the current JPKI circuit**, and uses an
explicitly synthetic root gate. The unmodified production gate must reject that
issuer. A corrupted proof and a different order must fail before money moves;
the valid proof must atomically transfer 100,000 test-token units, increment
the count/spend, and reject replay. No private keys are saved or printed.

Observed locally on 2026-09-21: all 47 contract tests passed. The real-proof
synthetic-issuer purchase passed, with 538,957 local gas and an 11,205 ms host
proof run using two threads. This is **not an iPhone speed comparison or an Arc
purchase**. CI repeats the cryptographic test and saves `.build/catalog-age-*/result.json`.

## Remaining integration

This is unaudited research code. A live route still needs a reviewed deployment,
the correct token/gate pins, explicit native owner delegation and revocation UX,
merchant quote signing, sponsorship and durable settlement/recovery, and actual
iPhone acceptance. Removing the local-chain guard alone does not provide those.
This contract's execution protocol is not bare x402 EIP-3009; an explicit,
reviewed settlement integration is required. Do not advertise automatic x402
payments, MynaWallet support or regional eligibility from this local test.

Age privacy does not hide wallets, amounts, recipients or policy limits.
Existing gate/circuit trust boundaries (including no certificate-revocation
check) still apply. Region/campaign eligibility and one-person-one-claim are
separate, unimplemented trust and proof requirements.
