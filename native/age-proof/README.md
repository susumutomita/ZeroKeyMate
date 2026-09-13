# Native signed-card age proof

Separate from Verity's spending-policy runtime. Build the reviewed masked backend
with `python3 scripts/build-age-evm.py`, then
`python3 scripts/build-age-native.py --ios`. The second command creates unsigned
static frameworks for device and Simulator and a local Swift-package link. It
never installs the app or uses an Apple signing identity.

The C API consumes private JSON in memory and public setup file paths. The caller
must check fixed setup hashes first. It returns only a verified public proof and
public inputs, uses fixed error codes, clears output on failure, and serializes
calls. It suppresses Rust panic payloads while a proof runs, including Rayon
workers; previous panic handling resumes outside the call. No private-input
file, log, model, network or wallet operation is implemented here. This does not
guarantee erasure of every memory copy or prevent an OS crash dump.

The C ABI cannot interrupt a running proof. The application checks cancellation
before and after it, discards the result, and must not proceed to checkout after
cancellation. The Swift package explicitly reports unavailable without the
generated runtime; it never substitutes a simulated proof.

EVM point serialization adapts the public MIT-licensed ProveKit PR #447 exporter
pinned by `config/age-proof-sources.json`; its notice is preserved in
`docs/third-party/provekit-groth16-LICENSE.txt`. The new adapter is Apache-2.0.
The backend is experimental, not independently audited, and the current setup
is single-party test setup. Do not use it on mainnet.

Tests use only the repository's fake certificates and signatures. Run
`RAYON_NUM_THREADS=2 python3 scripts/test-age-native.py`, then
`node scripts/test-age-evm.mjs .build/age-proof-engine/artifacts --native`.
On iOS, stage the pinned public resources and run `NativeAcceptance/AgeProofTests`.
Physical-card authenticity, revocation handling and physical-phone resource
limits remain separate acceptance boundaries.
