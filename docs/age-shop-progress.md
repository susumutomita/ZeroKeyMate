# Physical-card age checkout: implementation checkpoint

Updated 2026-09-12. This is **not a completed purchase flow**. Do not mark the
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

1. An age circuit must verify government certificate/card signatures and bind
   private DOB to a valid signed field, current reference date and order. The
   existing `mate_policy` circuit proves spending policy only. Calling local Swift
   validation before proving arbitrary DOB would **not** solve this.
2. Produce a proof locally on the iPhone that an EVM contract can verify. The
   pinned ProveKit source contains a gnark recursive verifier, but a working
   exported Solidity verifier, small public-input binding, safe setup lifecycle,
   mobile/runtime integration and execution resource budget remain unverified.
   Do not replace this with an attestor signature and call it direct ZK checking.
3. Implement the age gate and proof submission. Current `/age` only queries a
   proposed `isOrderAgeVerified` ABI. There is **no deployed gate** and this route
   does not yet accept a ZK proof. Its address and code hash remain blank.
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
- Shop: 28 tests passed. Protocol/schema tests use the actual x402 SDK; SQLite
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
