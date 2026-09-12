"""Exercise the real host FFI with repository synthetic witnesses only.

Writes only public proofs and non-sensitive acceptance metrics. No witness
files are produced here; the fixed synthetic inputs came from the circuit test.
"""
from pathlib import Path
import ctypes
import json
import time
import tomllib

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / ".build/age-proof-engine"
OUT = BASE / "artifacts"
runtime = ctypes.CDLL(str(BASE / "target/release/libmate_age_ffi.dylib"))
prove = runtime.mate_age_prove
prove.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t]
prove.restype = ctypes.c_int32
pkp = str(OUT / "age.pkp").encode()
pkv = str(OUT / "age.pkv").encode()


def run(name, expected=0, folder=None):
    values = tomllib.loads((OUT / "inputs" / (name + ".toml")).read_text())
    payload = json.dumps(values).encode()
    input_buffer = ctypes.create_string_buffer(payload)
    output = ctypes.create_string_buffer(bytes([255]) * 640, 640)
    start = time.monotonic()
    status = prove(pkp, pkv, input_buffer, len(payload), output, 640)
    assert status == expected, (name, status)
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
    return (proof, round(time.monotonic() - start, 3))


first, elapsed = run("valid", folder="native-evm")
second, _ = run("valid", folder="native-second-evm")
assert first[256:320] != second[256:320], "Native commitment did not change"
rejected = ["changed-order", "changed-nonce", "underage", "tampered-date", "bad-card-signature", "bad-certificate-signature"]
for name in rejected:
    run(name, expected=4)
    print("Native rejection: " + name, flush=True)
record = {"syntheticOnly": True, "hostNative": True, "physicalDevice": False,
          "nativeSeconds": elapsed, "proofBytes": 384, "publicInputs": 8,
          "sameWitnessCommitmentsDiffer": True, "rejected": rejected,
          "evmAcceptance": "Run test-age-evm.mjs .build/age-proof-engine/artifacts --native"}
(OUT / "native-acceptance.json").write_text(json.dumps(record, indent=2) + "\n")
print(json.dumps(record))
