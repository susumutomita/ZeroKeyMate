"""Exercise the real host FFI with repository synthetic witnesses only.

Writes only public proofs and non-sensitive acceptance metrics. No witness
files are produced here; the fixed synthetic inputs came from the circuit test.
"""
from pathlib import Path
import argparse
import ctypes
import hashlib
import json
import platform
import time
import tomllib

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / ".build/age-proof-engine"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--artifacts', default='.build/age-proof-engine/artifacts')
OUT = (ROOT / parser.parse_args().artifacts).resolve()
assert OUT.is_relative_to(ROOT / '.build'), 'Use an isolated local test artifact directory'
library = BASE / 'target/release' / ('libmate_age_ffi.dylib' if platform.system() == 'Darwin' else 'libmate_age_ffi.so')
runtime = ctypes.CDLL(str(library))
class Metrics(ctypes.Structure):
    _fields_ = [(name, ctypes.c_uint64) for name in [
        'version', 'worker_threads', 'total_us', 'prover_load_us', 'input_parse_us',
        'witness_and_proof_us', 'verifier_load_us', 'verify_us', 'encode_us']]


legacy = runtime.mate_age_prove
legacy.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t]
legacy.restype = ctypes.c_int32
prove = runtime.mate_age_prove_measured
prove.argtypes = legacy.argtypes + [ctypes.POINTER(Metrics)]
prove.restype = ctypes.c_int32
pkp = str(OUT / "age.pkp").encode()
pkv = str(OUT / "age.pkv").encode()


measurements = []


def run(name, expected=0, folder=None, legacy_abi=False):
    values = tomllib.loads((OUT / "inputs" / (name + ".toml")).read_text())
    payload = json.dumps(values).encode()
    input_buffer = ctypes.create_string_buffer(payload)
    output = ctypes.create_string_buffer(bytes([255]) * 640, 640)
    metrics = Metrics(*([2**64 - 1] * 9))
    start = time.monotonic()
    status = legacy(pkp, pkv, input_buffer, len(payload), output, 640) if legacy_abi else \
        prove(pkp, pkv, input_buffer, len(payload), output, 640, ctypes.byref(metrics))
    elapsed = time.monotonic() - start
    assert status == expected, (name, status)
    if not legacy_abi:
        measured = {key: getattr(metrics, key) for key, _ in metrics._fields_}
        assert measured['version'] == 1 and measured['worker_threads'] == 2
        parts = [v for key, v in measured.items() if key.endswith('_us') and key != 'total_us']
        assert sum(parts) <= measured['total_us'] <= elapsed * 1_000_000 + 1_000
        assert measured['prover_load_us'] > 0 and measured['witness_and_proof_us'] > 0
        if not expected:
            assert measured['verify_us'] > 0 and measured['encode_us'] > 0
        measurements.append({'syntheticFixture': name, 'status': status, **measured})
    if expected:
        assert output.raw == bytes(640), "A failure returned data"
        return None
    proof = output.raw[:384]
    inputs = [int.from_bytes(output.raw[i:i+32], "big") for i in range(384, 640, 32)]
    reference = [int(n) for n in (OUT / "evm/inputs.txt").read_text().split()]
    assert inputs == reference
    destination = OUT / folder
    destination.mkdir(exist_ok=True)
    (destination / "proof.hex").write_text("0x" + proof.hex())
    (destination / "inputs.txt").write_text("\n".join(map(str, inputs)) + "\n")
    return (proof, round(elapsed, 3))


first, elapsed = run("valid", folder="native-evm")
second, _ = run("valid", folder="native-second-evm")
assert first[256:320] != second[256:320], "Native commitment did not change"
run('valid', folder='native-legacy-evm', legacy_abi=True)
# Invalid calls reset both outputs, without reading private buffers or paths.
empty = ctypes.create_string_buffer(bytes([255]) * 640, 640)
invalid_metrics = Metrics(*([2**64 - 1] * 9))
assert prove(None, None, None, 0, empty, 640, ctypes.byref(invalid_metrics)) == 1
assert empty.raw == bytes(640)
assert invalid_metrics.version == 1 and invalid_metrics.witness_and_proof_us == 0
rejected = ["changed-order", "changed-nonce", "underage", "tampered-date", "bad-card-signature", "bad-certificate-signature",
            "missing-policy", "wrong-policy", "unknown-critical"]
for name in rejected:
    run(name, expected=4)
    print("Native rejection: " + name, flush=True)
record = {"syntheticOnly": True, "hostNative": True, "physicalDevice": False,
          "nativeSeconds": elapsed, "proofBytes": 384, "publicInputs": 8,
          "sameWitnessCommitmentsDiffer": True, "rejected": rejected,
          "backend": "masked-groth16", "os": platform.system(), "osRelease": platform.release(),
          "architecture": platform.machine(), "measurements": measurements,
          "cacheNote": "First and subsequent calls in this process; OS file caches are not flushed. No cold-device or p95 claim.",
          "nativeLibrarySHA256": hashlib.sha256(library.read_bytes()).hexdigest(),
          "evmAcceptance": "Run test-age-evm.mjs .build/age-proof-engine/artifacts --native"}
(OUT / "native-acceptance.json").write_text(json.dumps(record, indent=2) + "\n")
print(json.dumps(record))
