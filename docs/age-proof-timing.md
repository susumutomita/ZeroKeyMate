# Local age-proof timing

The current checkout uses the pinned, masked Groth16 backend. It does not use
WHIR or a recursive wrapper. A previous iPhone 16 Pro result of about 12 seconds
measured `AgeProofService.prove`, not an isolated Groth16 primitive. NFC and
store/network time are outside that interval; the native call includes key
loading, input parsing, witness construction, proving, local verification and
encoding. Resource hash verification may already have happened during order
preparation and is then outside the displayed interval.

The native measured ABI reports monotonic microsecond durations for:

- loading the public prover key;
- parsing the in-memory input;
- witness construction and proof generation together;
- loading the public verifier key;
- verifying the generated proof locally;
- encoding the proof and public inputs for the EVM;
- total native call time, including unclassified overhead and cleanup.

The upstream prover exposes witness construction and proving through one call.
Their combined duration must not be labeled pure Groth16 time. The sum of phase
values may be lower than the total because pool setup, validation and cleanup
are not individual phases. Two worker threads remain fixed; no protocol,
circuit, setup, contract, resource hash or thread-count change is made.

The iPhone shows successful measurements under **Purchase details → Proof
timing**. They stay in the existing device-only saved order. The network envelope
continues to contain only `proof` and `rootKeyHash`. No witness, card information,
path or device identifier is included in timing records. Old saved orders without
the optional phase data still decode. App failures/cancellations do not expose a
partial proof or invent a successful timing result. The C ABI exposes partial
phase measurements and a status on failure for synthetic host tests only.

## Reproduce with synthetic credentials

```sh
python3 scripts/build-age-evm.py
python3 scripts/build-age-native.py       # macOS or Linux host
python3 scripts/test-age-native.py
node scripts/test-age-evm.mjs .build/age-proof-engine/artifacts --native
```

On Apple Silicon, `build-age-native.py --ios` additionally produces unsigned
Simulator/device libraries. The native acceptance tests exercise the real Swift
adapter; compiling a source-only app is not evidence of that ABI working.

`native-acceptance.json` records two measured successful calls, invalid-witness
rejections, backend/OS/architecture and native library hash. The original C ABI
is also exercised, and all three valid outputs must verify on a local EVM.
Tests check the timing schema, phase sum, failure-buffer clearing, proof size,
public-input binding and randomized commitments. CI repeats host-native and EVM
acceptance rather than relying on a Swift build with the runtime absent.

The first/subsequent calls are only first/subsequent in the test process. OS file
caches are not flushed: do not call them cold/warm device results, publish p95
from two samples, or compare host numbers to the previous phone result. This
adds measurement, not a claimed speedup. WHIR privacy review and its separate
verifier/wrapper integration remain independent work in issue #54.
