# Independent verification of an exported proof

This workflow supports Issue #14. It does not complete physical acceptance by itself.

1. Record the installed source commit and preserve that build's `Resources/Proofs` directory, including its manifest. Do not rebuild setup keys between generation and verification.
2. On the physical iPhone, enable airplane mode and turn Wi-Fi off. Record those settings and the actual device model/OS locally. Generate a proof in **Try private rules on this device**. Record the first run separately from at least three repeated runs, including time, size, measured peak memory and thermal state. This command does not collect those device measurements.
3. Record when connectivity is re-enabled for transfer. Use **Prepare proof file for sharing → Share proof file** to export the actual `.np` to the Mac. Preserve the original file.
4. Build the independent verifier and verify the export:

```sh
cargo +nightly-2026-03-04 build --release --locked --manifest-path services/verifier/Cargo.toml
python3 scripts/verify-exported-proof.py /path/to/phone-export.np \
  --resources /path/to/preserved-build/Proofs \
  --report .build/export-verification.json
```

The report path must be new and its parent directory must exist. `--verifier /path/to/mate-verify` selects an already built verifier. The tool invokes it directly without a shell or network requests. It snapshots the proof and key into a temporary directory; the original export is never modified. Each invocation has a 120-second deadline.

Acceptance requires three checks: the original succeeds, a copy with one bit changed fails with a recognized verification or decoding error, and the original succeeds again. The report distinguishes a decoding rejection from a cryptographic verification rejection. Loader failures, crashes, timeouts and unexpected errors fail the command. The temporary copies are removed afterwards.

The saved JSON includes hashes of the original proof, verifier key, manifest and verifier executable, plus the verification timestamp. It omits public input statements, local file paths and verifier output. It is created with owner-only permissions and is never overwritten. Keep it in `.build`, outside version control; review any evidence before publishing it.

A matching manifest proves internal consistency, not the identity of the installed app. Device origin and offline operation remain explicitly `not-verified` in this report. Complete those observations with actual device footage and a matching source/build record. Memory and thermal evidence must come from measurement on the iPhone, not the Mac verifier or Simulator.

An unsuccessful command exits nonzero and does not create an acceptance report. If a report already exists, preserve it and choose a new filename. For a key mismatch, locate the resources from the installed build; generating new setup keys will not repair an old proof. For verifier failures, inspect the original file with the verifier locally rather than publishing raw diagnostic output.
