# Card read succeeds, then local age proving fails

The former circuit rejected every critical extension except keyUsage and SAN.
The J-LIS physical signing-certificate profile requires **critical
certificatePolicies (2.5.29.32)**, containing policy
`1.2.392.200149.8.5.1.1.20` and the CPS qualifier. The old synthetic fixture omitted
that required extension, so it did not cover a profile-conforming certificate.
See [J-LIS profile 3.2, printed page 10 / PDF page 14](https://www.j-lis.go.jp/file.jsp?/file/13_profile_genkou.pdf=).

On 2026-09-13, adding that extension to a freshly generated synthetic certificate
reproduced a constraint rejection with the original pinned proving key. The
original phone-native fixture test had passed, including its underage and changed
order rejections; that success did not establish real-card compatibility.

The circuit and the Swift certificate parser now explicitly process the physical
signing policy and CPS qualifier. Unknown critical extensions, a missing policy,
and the wrong policy remain failures. The fixture generator includes the required
extension, and negative fixtures cover those cases. Test RSA keys are created in
memory and are never stored. No private implementation from another repository
was copied for this fix.

The input from a successful card read stays in memory only while this order's
proof attempt is active or explicitly retriable. It is dropped on backgrounding,
closing, order expiry and proof success. It is never a saved-order or network
field. Native work already in progress cannot currently be interrupted mid-call;
its result is discarded after cancellation. Only the public proof may be saved
for an exact, order-bound verification retry. The password is cleared before NFC.

Proof failures no longer automatically return to password entry. Saved failure
information consists only of fixed diagnostic categories (`AGE-*`), with no raw
error, certificate, signature, date, witness or path. Purchase-status questions
are answered by validated order recovery. A proof, age approval or transaction
hash alone is not a completed purchase: success still requires matching receipts
from the two configured Arc RPC providers.

Updating this circuit requires a new public test setup, matching EVM verifier
and gate, shop coordinates, and iPhone resources. Reusing the previous deployed
verifier would keep rejecting the new proofs. The setup remains an experimental
single-party test setup; revocation is not checked. Synthetic acceptance is not
physical-card purchase acceptance.

Validation on the replacement setup:

- Core `make test` and `make -o project build-ios` pass. The macOS core test
  requires normal Security.framework access; a sandbox-blocked trust evaluation
  is not a reason to remove certificate checks.
- 22 native regression/UI tests pass for card capture, password entry, checkout
  questions and failure recovery. Physical-card data is not used by those tests.
- The actual host native FFI accepts the policy-bearing synthetic witness;
  9 invalid native inputs return failure with no proof output. The circuit
  acceptance rejects 20 negative witnesses, including missing/wrong policies
  and an unknown critical extension.
- The FFI proof verifies in the actual EVM verifier. The deployed government-root
  gate rejects the synthetic test CA; only a local synthetic-root test gate
  accepts it. Changed public inputs and invalid proofs are rejected.
- Fresh Solidity export and compilation reproduce deployment package SHA-256
  `07f44f7aaff63da2bed7254878e93df692342168f9dac54a3f47fa3a0d3504a9`.
  The replacement contracts are deployed on Arc Testnet and checked against
  their full expected runtime through both fixed RPC providers.

The strict one-policy/one-CPS shape is the currently supported J-LIS profile,
not a general statement that all other X.509 policy structures are invalid.
No CPS URL is fetched. Existing strict DER, unique DOB, original signed TBS,
signature, expiry and government-root constraints remain in place.

See [the current live deployment](arc-live-status.md) for phone installation and
physical acceptance status. Synthetic tests do not establish a real-card purchase.

On 2026-09-13, build 6 completed a user-operated physical-card purchase. The
user supplied the successful 12.0 s local-proof screen, and both Arc providers
confirmed the 0.10 test-USDC settlement linked in the live-status document.
This closes the single real-card main-path acceptance, not all card variants,
repeat/recovery cases, revocation support or unattended delegated payment.

An additional synchronous XCTest witness test was interrupted by iOS process-exit
watchdog while its main thread waited for native work; this was not a circuit
rejection. The test now runs native proving on a background task, matching the
app service. The raw native valid/invalid-input test passed on the same phone.
