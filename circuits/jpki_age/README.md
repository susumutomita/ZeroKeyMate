# Private signed-card age proof

This circuit proves age >= 20 from a **signed physical JPKI certificate**, with
possession of its signing key demonstrated by an order-bound card signature.
It does not accept an unsigned birth date or trust the app's verification result.
No physical card or mobile proof has been tested with this circuit yet.

The constrained statement checks a narrow v3 RSA-2048/SHA-256 certificate profile:
canonical bounded DER, signed TBS, validity over the entire 15-minute order,
signing key usage, unique extensions and signed SAN otherName DOB
`1.2.392.200149.8.5.5.4`. DOB is one era-code digit followed by eight Gregorian
digits; incomplete dates fail. RSA exponent 65537 is fixed for root and card.
The root signs TBS; the card signs exactly 98 bytes:
`"ZeroKeyMate age authentication v1\0" || orderHash[32] || nonce[32]`.

| Public input index | Type | Meaning |
| --- | --- | --- |
| 0, 1 | u128, u128 | Order hash, big-endian high/low halves |
| 2, 3 | u128, u128 | Order/payment nonce, high/low halves |
| 4, 5 | u128, u128 | SHA-256 of the root RSA modulus, high/low halves |
| 6 | u64 | Order reference timestamp, Unix seconds |
| 7 | u64 | Order expiry, Unix seconds |

Private inputs are the signed TBS (zero-padded to 2048 bytes), length, certificate
signature, root modulus, card signature and RSA reduction hints. The card modulus
and birth date are extracted within the signed structure. Padding/hashing are
constrained directly with the standard SHA-256 compression black box. No hashing
hint or private witness is sent to the shop. The RSA library constrains its
unconstrained arithmetic results; its reduction hint is not a trust anchor.

Age uses the Gregorian twentieth anniversary at midnight JST. For the unusual
Feb 29 anniversary in a non-leap century, this implementation conservatively
uses March 1. This is an explicit prototype policy, not legal certification.

`MateAgeGate` pins the official 2019/2023 signing-root modulus hashes and their
validity periods. A proof under an arbitrary test root is **not** identity proof
and is rejected by the production gate. It also binds the expected order hash,
nonce and exact reference/expiry interval before calling the circuit-specific
Groth16 verifier. The Worker recomputes inputs from its persisted order and uses
`eth_call`, then repeats verification before settlement. No age transaction or
attestor signature is needed. The public RPC receives the proof and order values.

Certificate revocation is **not checked**. The 2048-byte TBS cap, UTCTime validity
and otherName-only SAN are a deliberately narrow profile; unsupported real cards
fail closed. There is no anonymous payment or shipping claim.

## Reproduce

With the existing ProveKit 1.0.1 tool installed and Python cryptography 49.0.0:

```sh
python3 scripts/test-jpki-age.py
```

This compiles the actual source, proves/verifies a synthetic signed adult and
rejects 17 bad witnesses. Ten SHA reference cases and nine calendar boundary
cases exercise the same helper source. It uses hiding WHIR; it does **not** test
EVM or iPhone proving. Evidence is in `.build/jpki-age-acceptance/acceptance.json`.

For the separate experimental direct EVM backend (Rust nightly-2026-03-04, Node,
Anvil and Python cryptography required):

```sh
python3 scripts/build-age-evm.py
node scripts/test-age-evm.mjs .build/age-proof-engine/artifacts
```

The build pins public ProveKit PR #447, its compiler compatibility patch and
dependency archive hashes. It preserves compiler constraint checks and patches
the upstream Solidity accumulator from four to five words to contain all writes.
The real EVM test covers proof/input mutation, expected-order binding, expiry,
official-root rejection of synthetic credentials and an adjacent memory canary.
All local-chain keys are generated in memory only. Nothing is deployed publicly.

This backend is an **unaudited upstream PR with single-party test setup**, not the
shipping iPhone runtime or a production ceremony. Rebuilding setup changes the
verifier. The generated proof, PKP/PKV and verifier must remain a matching set,
pinned by the recorded provenance and deployed runtime hashes. Never treat these
local tests as approval to replace the current native runtime or open checkout.


### Commitment privacy

The upstream PR's exported BSB22 commitment is deterministic without a separate
mask; randomized Groth16 A/B points do not repair that. Unpatched artifacts from
the initial experiment are **not hiding** and must never receive real credentials.
The reproducible build now applies `provekit-groth16-hiding.patch`, following the
published gnark GHSA-9xcg-3q8v-7fq6 / #1245 fix: add a free `mask * 1 = mask` row
**after** optimization, include that wire in the private commitment and generate
a fresh uniform field element inside the prover on every call. Setup rejects a
zero mask basis. Solver-only virtual columns are remapped to make room for the
new real wire; the mask is neither an ABI input nor a serialized proof field.

The acceptance build proves the same exact witness twice, verifies both, and
compares the actual exported commitment bytes, not merely the randomized whole
proof. This regression supports the source review; it is not a formal audit.
Old unmasked preparation files are incompatible with the new prover metadata.
