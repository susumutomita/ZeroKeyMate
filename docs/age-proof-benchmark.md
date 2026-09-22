# Native age-proof comparison

Settings → **Age proof benchmark** selects Groth16 or experimental WHIR on the
same device. Both use the existing `mate_jpki_age` circuit, the same eight public
inputs and the same fixed, public synthetic credential. The Rust ABI has **no
credential-input or proof-output argument**. It cannot receive a real card scan
or authorize checkout. Purchases continue to use their existing Groth16 gate.

The app reports witness creation + proving, local verification, native total,
resource validation time, serialized size, OS/device identifier, worker count,
and thermal state. Each result requires successful verification and rejection
of the same proof after changing its order public input. Only measurement
reports can be shared. No proof, credential, key or network request is exported
by this experiment.

## What the numbers mean

- `witnessAndProofMicroseconds` is one upstream call: witness generation and the
  prover are not individually timed.
- Native total includes key loading, input parsing, witness/proving, verifier
  loading, verification and serialization. Two Rayon workers are used.
- The app hashes public resources before first use. That time is separate and
  cached within the current benchmark service. The native prover still reloads
  its keys on every sample.
- The modified-order rejection is a separate duration. It checks statement
  binding, not zero-knowledge, revocation or production identity assurance.
- The native ProveKit file format is used for both sizes. The existing 384-byte
  Groth16 EVM proof representation is a different encoding.
- File caches are uncontrolled. Run multiple interleaved samples with a stable
  thermal state and record the device. A simulator, a Mac or a single result is
  not an iPhone speed claim. Avoid measuring while the host is compiling.

WHIR privacy for actual government credentials is **not validated here**.
Wrapped WHIR remains unavailable: the pinned exporter and recursive verifier
have incompatible transcript/configuration formats. Current upstream main also
explicitly rejects gnark export for its new protocol configuration. This work
neither fabricates a wrapped proof nor changes an immutable on-chain verifier.
See [the existing timing evidence](age-proof-timing.md) and the
[project status](../README.md) for baseline limitations.

## Reproduce and install public resources

1. Build the reviewed age runtime with `python3 scripts/build-age-native.py --ios`
   after the existing age engine setup. This compiles the benchmark alongside the
   unchanged purchase ABI from the pinned public ProveKit revision and patches.
2. Use that revision's CLI and the vendored age circuit to prepare WHIR:

   ```sh
   provekit-cli prepare PATH_TO_VENDORED_JPKI_CIRCUIT --backend whir \
     --pkp OUTPUT/age-whir.pkp --pkv OUTPUT/age-whir.pkv
   ```

   The committed `config/age-benchmark-pins.json` identifies the reviewed setup.
   Newly generated artifacts may differ; review the source, statement, fixture
   and artifact hashes before changing pins. Staging never trusts new keys just
   because proof verification succeeded.
3. Run `python3 scripts/stage-age-benchmark.py OUTPUT`. The command accepts only
   the pinned public key pair. Stage the normal `age.pkp`/`age.pkv` with their
   existing `config/age-runtime-pins.json` separately; they are also the baseline.
4. Run the host checks:

   ```sh
   python3 scripts/test-age-benchmark.py --whir-directory OUTPUT \
     --groth16-directory PATH_TO_PINNED_GROTH16_KEYS
   ```

   This reproduces the compiled synthetic fixture from the repository's public
   certificates, checks both key pairs, runs two samples of each actual native
   prover, rejects changed orders and backend mismatches, and writes only local
   metrics to `.build/age-proof-engine/synthetic-benchmark.json`.
5. Build/install the app normally. The physical-device test
   `NativeAcceptance/AgeBenchmarkTests` runs four interleaved synthetic samples
   and attaches `synthetic-age-backend-timings`. It skips explicitly if the
   matching native runtime or public setup has not been staged.

Source-only CI can build the UI but cannot establish native/device timings.
No real card, private wallet key, signature request or chain deployment is
required for this comparison.
