# Physical-card age checkout: implementation checkpoint

Updated 2026-09-13. This is **not a completed purchase flow**. Do not mark the
project finished from unit tests, a simulator, a catalog page or a configured URL.

## Working increment

- An explicit iPhone NFC session reads the input-assistance application's birth
  date with the four-digit PIN. PIN verification is sequential and never retried
  automatically. The Settings > Age verification screen uses this diagnostic
  path only and says that checkout remains locked.
- The separate `MyNumberNFCService.authenticate(pin:challenge:)` path reads the
  JPKI signing certificate and asks the card to sign a domain-separated order
  hash and nonce. It requires the **6–16 uppercase alphanumeric signing PIN**,
  not the four-digit input-assistance PIN. It is not yet called by a purchase UI.
- Local Security.framework verification uses only fingerprint-pinned official
  2019/2023 J-LIS roots, disables network fetching, verifies the certificate chain
  and card signature, and reads DOB only from the signed SAN otherName field.
  Unknown/partial dates are rejected. The returned credential explicitly has
  `revocationChecked = false`; this is not completed eKYC or shop age approval.
- PINs, certificates, raw responses, DOB and card signatures are not logged,
  persisted or transmitted by either reader. Cancellation resolves an outstanding
  APDU continuation so it does not retain a read indefinitely.
- `services/shop` contains an English, responsive Workers storefront and D1
  order API for one 0.10 test-USDC Mate Lager on **Base Sepolia (84532)**.
  Existing Arc service routes are separate and unchanged.
- Orders commit to product, quantity, payer, merchant, token, chain, amount,
  expiry, age threshold and payment nonce. A capability header retrieves the
  same persistent order across retries. The Worker uses the actual x402 v2 SDK
  and public test facilitator interface.
- Payment is reserved in D1 before settlement. An uncertain result stays pending
  and looks for the original `AuthorizationUsed` event. Completion requires a
  successful canonical receipt, two confirmations, the exact nonce and matching
  USDC transfer. A pending payment is never replaced with another nonce.
- After a one-minute attempt lease, the client may resubmit only the exact
  original signed header while still valid. Concurrent retries reserve one
  attempt. Transaction hashes are stored before receipt polling; GET never pays.
- New orders require live chain/clock/code/gate/D1/facilitator readiness. Fixed
  resource-key Workers rate limits bound API/creation traffic without sending IP
  addresses to the limiter, and D1 caps the test shop at 1,000 stored orders.
- Settings/request screens now reuse one presentation. This fixes quick switches
  that previously left an old form visible while a replacement sheet opened.

## Still required (implementation work, not a request for the user to debug)

1. The actual signed-card age circuit is implemented and checked with synthetic
   certificates. Validate its deliberately narrow physical-card certificate
   profile on a real card; no physical identity acceptance has been performed.
2. Connect the implemented native age prover to the purchase/card UI and measure
   it on a physical phone. The separate native library, private Swift witness
   preparation, fixed setup hashes and actual Simulator proving now work.
   Cancellation discards a completed result; it cannot yet interrupt the backend
   halfway through. Desktop Groth16 and actual EVM verification pass, but
   this is an unaudited upstream branch with single-party test setup. Production
   setup/security review remains required; no mainnet use is authorized.
3. Publish matching verifier/gate and configure the Worker only after the native
   flow is ready and the specific deployment credentials are authorized. `/age`
   now accepts a proof and directly verifies it with the contract via `eth_call`;
   no public contract, Worker or age transaction has been deployed by this work.
4. Implement the Mate beer-shopping tool and review/card/proof/payment/result
   sequence, persist the non-sensitive order context, and connect wallet signing
   under an explicit shop/purpose/amount delegation. The local model does not
   get signing keys, card data, arbitrary URLs or final payment authority.
5. Define credential revocation handling without disclosing a person's certificate
   or serial number to an unapproved endpoint. Do not claim revocation is checked.
6. Complete terminal settlement recovery after authorization expiry. Pre-broadcast
   failures can now retry the exact original authorization, but an expired
   authorization with no observed outcome remains pending. Preserve its nonce.
7. Validate the readiness probe and resource limits on deployed Workers, and
   confirm the configured limiter namespace IDs are unused in that account.
8. Publish Workers/D1 and the real testnet contracts, install on a physical iPhone,
   then run card tap + local proof + contract verification + x402 receipt together
   with the user. Recheck stand launch/wake limitations using Apple documentation;
   placing a phone on a stand is not permission to capture or sign.

## Validation recorded

- `make test`: passed (71 Swift tests, 58 Node tests, 13 Python tests).
- Unsigned `make build-ios` (skipping the `.env` configuration-generation target):
  passed after the NFC authentication/cancellation changes.
- Three real Simulator UI tests passed: card screen explicit start/PIN cleared on
  reopening, setup deferred/resumed without sensors, and editable unsent request.
- Shop: 31 tests passed. Protocol/schema tests use the actual x402 SDK; SQLite
  checkout tests inject RPC/facilitator failures. They are **not** a live payment
  or ZK verification. Wrangler dry-run build passed without deploying.
- Browser: desktop 1200px and mobile 393px inspected; no horizontal overflow at
  393px, price/request in first screen, availability retry works, unready request
  copy button disabled. Full purchase-flow usability is not yet testable.
- Physical card/PIN, device install, public gate, public payment: **not performed**.

## Permission boundary for continued work

The user approved 30-minute continued implementation/test/PR/merge, testnet
publication and eventual installation. They subsequently reserved existing
private keys, personal data, card PIN/touch and money-related authorization.
Respect the stricter boundary. Normal GitHub source-management authentication is
within the approved PR/merge scope; disable commit GPG signing rather than using
an existing signing key. Never read `.env`, seed phrases, wallet keys or deployment
secrets to discover what can be used.

When the relevant build/deployment is concrete, ask the user to authorize the
specific credential and action, not to paste secrets into chat:

| Later action | Credential/data and destination | Current state |
| --- | --- | --- |
| Publish test storefront | Cloudflare account authorization for this Worker/D1; no card data | Not used |
| Install iOS app | Apple Development signing identity, used locally by Xcode | No device signing performed |
| Deploy verifier | Explicitly approved testnet-only deployer and bounded Base Sepolia gas | No wallet key read or used |
| Buy one test item | iPhone signs the exact 0.10 test-USDC order for Base Sepolia; facilitator receives that limited authorization | Not signed or submitted |
| Authenticate physical card | User enters the relevant PIN on iPhone and touches card; private credential remains in memory on device | User will do this when awake |

Do not claim anonymous payments: the payer, recipient and amount are public.
Do not claim anonymous delivery: no shipping flow is implemented.

## Research and source evidence

Research and UX feedback were separately requested in ChatGPT and collected:
https://chatgpt.com/uc/6aa55289-77c4-83ea-b7d5-c807b6ed3b8b . Its conclusions are
leads, not implementation proof. Primary-source checks corrected the distinction
between an input-assistance date, a signed credential and an order-bound ZK proof.

The user-authorized CircuitBreaker revision reads a date but does not validate
government signatures; its circuit accepts an arbitrary age and its frontend uses
Sindri cloud proving. Only the public NFC APDU reference was adapted. Public source
revisions, licenses, J-LIS profile/root fingerprints and x402 docs are in SOURCES.md.

An ACTIVE thread heartbeat named `ZeroKeyMateの実機購入体験を完成させる` was registered
with ID `zerokeymate` at the user's explicit approval. It should resume from the
latest branch/PR and this checkpoint, not discard work or repeat initial research.

## Recursive verifier experiment (not a working age proof)

PR #38 contains the card/shop foundation. Its independent review caught a missing
zero in the JPKI AID; commit c751d0d fixes it and tests the full public APDU bytes.
`make test`, the unsigned iOS build, and 21 shop tests passed at that commit;
subsequent shop readiness/retry tests bring the shop count to 28.

The local ProveKit 1.0.1 export for the synthetic spending-policy proof succeeds,
but its pinned Rust exporter emits `narg_string` and `hints`; the Go recursive
verifier in the same source revision still expects `io_pattern`, `transcript`,
and a different blinding layout. An isolated CPU-only Go build succeeded, but
execution immediately failed with `deferred array too short: expected at least
8 elements, got 0`. No recursive proof, Solidity verifier, or setup artifacts
were produced. Do not patch in empty fields or claim this route works.

Artifacts are in ignored `.build/age-evm-probe/` (synthetic data only); logs are in
`/private/tmp/zerokeymate-recursive-probe.log`. The public Go 1.27.1 toolchain was
downloaded from go.dev and SHA-256 checked before extracting there. The shared
`.tools/provekit-source` and existing mobile runtime were not modified.

Separate ChatGPT research led to public ProveKit PR #470, which explicitly warns
that its later proof format 2.0 is incompatible with the Go verifier and that
witness openings are not hiding. The pinned 1.0.1 source still uses `WhirZkConfig`;
do not conflate it with #470 or upgrade to a non-hiding witness path for DOB.
PR #447 (`dd237e542403302186c8de4bd10df6e5c9b6725a`, still open) provides direct
Groth16+BSB22 Solidity export. Its public source is isolated under
`.build/age-groth16-source/` for examination; no mobile proof, resource budget or
trusted setup has been verified for it. This is a candidate to investigate,
not a completed replacement or an excuse to disclose private witnesses.


## Signed-card circuit and direct EVM increment — 2026-09-13

Branch `codex/jpki-age-proof` starts at merged PR #38 (`0774fd0`).
`circuits/jpki_age` verifies both RSA-2048 signatures, extracts DOB within signed
TBS, checks strict DER/profile/calendar/validity and binds the exact Swift card
challenge to the order. Eight public inputs pack the three public hashes into
u128 halves, plus reference/expiry. DOB, certificate, card signature and card key
are private. The government root modulus hash is public and pinned by the gate.

`MateAgeGate.verifyOrderAge` checks expected order/nonce, the exact 15-minute
window and official root validity before directly calling the proof verifier.
The Worker builds those inputs from its saved order, accepts only the 384-byte
proof and root hash, and verifies via `eth_call` with a bounded gas budget. It
stores the public proof for repeat verification immediately before x402 payment.
There is no attestor, age-signing wallet or age transaction. This is an intentional
replacement of the old proposed `isOrderAgeVerified` state-query interface.

Validation: the actual hiding WHIR age proof verified, 17 invalid witnesses were
rejected, 10 independent SHA vectors and 9 calendar boundary cases passed. The
same age statement also proved/verified with the isolated direct Groth16 backend,
and its real Solidity verifier and age gate passed on Anvil. The test verifies
all eight input mutations, changed expected order/nonce/expiry, expired proof,
malformed proofs, and rejection of the synthetic root by the official gate. It
uses a separate, explicitly generated test-only subclass to accept the synthetic
root for positive gate testing. No fake verifier is used.

The generated proof is 384 bytes and the masked verifier runtime 5,840 bytes;
direct verifier gas estimate was 369,793. These are desktop/local-EVM results,
not iPhone or Base Sepolia measurements. A boolean-returning gate must not be
gas-estimated directly: insufficient gas can yield false through its catch path.
The Worker uses an explicit 1,000,000 eth_call gas budget.

Separate ChatGPT feedback corroborated an upstream Solidity buffer-boundary bug;
local source inspection and a real EVM memory-canary test confirmed the fix.
`patch-age-verifier.py` pins the exact template hash and allocates five words for
two accumulator plus three ECMUL input words. A Noir beta.19 diagnostic in the
upstream SHA helper was avoided by directly constraining padding and byte packing.
The circuit now compiles with checks enabled and without that diagnostic.

Reproduction: `test-jpki-age.py` for the shipping-version WHIR circuit tests;
`build-age-evm.py` followed by `test-age-evm.mjs .build/age-proof-engine/artifacts`
for the separate experimental Groth16 path. Its public source archive hashes,
compiler patch and setup artifact provenance are recorded. It does not modify
`.tools/provekit-source`, the existing mobile runtime, `.env` or private keys.

Remaining immediately useful work: native age FFI and private witness preparation,
shop request/card/proof/payment/result UI, real worker-to-contract acceptance,
terminal expired-payment recovery. Card tap/PIN remains for the user when awake.


Privacy audit follow-up: source inspection found a deterministic BSB22 private
commitment in the candidate backend. This is the class described in gnark's
published GHSA-9xcg-3q8v-7fq6; successful proof verification did not establish
hiding. All earlier unmasked Groth16 artifacts are synthetic-only and must not
be used for real credentials. The isolated backend now includes the published
post-optimization random-mask method, with solver-column remapping, a nonzero
mask-basis setup check, new prover metadata and a repeated-identical-witness
commitment test. The reproducible masked build passed: identical private inputs
produced different commitment points, both proofs passed native and real EVM
verification, all eight public-input mutations failed, and the official gate
rejected the synthetic root. This is regression evidence, not an independent
cryptographic audit. No real personal data was used in these experiments.

A further external ChatGPT review request was rejected by automatic approval
review because its payload included unpublished cryptographic design details.
That payload was not sent; the work continued using read-only public security
advisories and source code. Do not retry sending the rejected design indirectly.

PR #39 review follow-up: all SHA dependencies (including transitive SHA-1 and
SHA-512 manifests) are now checksum-pinned and locally vendored before prepare.
Age verification now requires agreement between the Base and PublicNode RPCs
at a common recent block, including chain, block hash/time, gate bytecode and
the proof result. This prevents one fabricated RPC response from unlocking an
order. It remains a 2-of-2 provider trust boundary, not light-client verification;
both-provider collusion is outside that guarantee. x402 USDC settlement does
not independently invoke the age gate. See the shop README for this assumption.

## Native age increment — 2026-09-13

Branch `codex/native-age-proof` starts at PR #39's review-fix commit `6d85e76`.
`JPKIAgeWitness` rechecks the government credential and exact card challenge,
retains the original signed TBS bytes, computes RSA reduction hints in Swift,
and exposes private inputs only through an in-memory local-prover callback.
Its synthetic result matches independently computed Python cryptography hashes.
The public entry cannot inject a root; private input diagnostics are redacted.

`native/age-proof` provides a separate Rust C ABI and Swift package around the
masked Groth16 backend. It does not clone a cached full prover or write witness
files. It returns only a verified 384-byte proof and eight public field elements;
errors return fixed codes and zeroed output. During proving, panic payloads are
suppressed, including worker threads. Swift/Data copies are not guaranteed to be
securely erased. No existing Verity/policy runtime source was modified.

Both unsigned iOS libraries build. A named static framework fixes Xcode's shared
module-map collision with Verity. The application has a separate `AgeProofService`
actor, fixed public parameter hashes and bounded-memory file hashing. Missing
runtime/resources remain unavailable. The setup is about 628.7 MiB plus a 12.5 MiB
verifier; physical phone peak memory and latency are still unmeasured.

Validation: `make test` passed with 76 Swift, 58 Node and 13 Python tests. Unsigned
application build with both native libraries passed. Host FFI generated two
different commitments, matched all public inputs, rejected six invalid witnesses,
and both actual proofs passed the EVM verifier/gate. The focused iPhone 17 Pro
iOS 26.5 Simulator test **ran and passed, zero skips**: two native age proofs,
different commitments, underage and changed-order rejection. Result bundle:
`.build/native-evidence/age-acceptance-20260913`. This is not a physical card test.

Reproduce with `build-age-evm.py`, `build-age-native.py --ios`,
`stage-age-resources.py`, and the focused `NativeAcceptance/AgeProofTests` target.
The reviewed public setup hashes are in `config/age-runtime-pins.json` and the
application's `AgeProofPins.swift`; regenerating the random test setup requires
reviewing/updating those pins and its matching shop verifier. A new setup can be
tested separately with `--artifacts .build/age-source-validation/artifacts`.
No real card, existing private key, device signing identity, public deployment,
or payment was used. The beer tool, purchase UI and payment connection are next.
