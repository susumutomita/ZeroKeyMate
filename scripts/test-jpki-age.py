"""Compile the actual age circuit, prove a synthetic adult and reject bad witnesses.

Uses ProveKit 1.0.1's hiding WHIR path. This is NOT an EVM/mobile acceptance test.
The EVM/mobile backend has a separate acceptance suite.
"""
from age_sources import CONFIG, DEPENDENCIES, vendor_circuit
from hashlib import sha256
from pathlib import Path
import importlib.util
import json
import os
import re
import subprocess
import time
import shutil
from datetime import datetime, timezone, timedelta

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / ".build/jpki-age-acceptance"
CLI = ROOT / ".tools/bin/provekit-cli"
spec = importlib.util.spec_from_file_location("fixtures", ROOT / "scripts/jpki-age-fixtures.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def run(name, *args, reject=False):
    start = time.monotonic()
    with (OUT / (name + ".log")).open("w") as log:
        result = subprocess.run([str(CLI), *map(str, args)], cwd=ROOT,
                                env={**os.environ, "RAYON_NUM_THREADS": "2"}, stdout=log, stderr=log)
    output = (OUT / (name + ".log")).read_text()
    plain = re.sub(r"\x1b\[[0-9;]*m", "", output)
    assert "panicked at" not in plain and "bug:" not in plain, f"Compiler/runtime diagnostic: {name}"
    if reject:
        assert result.returncode != 0, f"Invalid witness accepted: {name}"
        assert "While proving Noir program statement" in plain, f"Not a witness rejection: {name}"
        assert "Failed assertion" in plain or "Failed to solve program" in plain, f"Unexpected rejection: {name}"
    else:
        assert result.returncode == 0, f"Failed: {name}; see its synthetic-only log"
    print(("Rejected " if reject else "Passed ") + name, flush=True)
    return round(time.monotonic()-start, 3)


OUT.mkdir(parents=True, exist_ok=True)
cases = module.fixtures(OUT / "inputs")
circuit = vendor_circuit(OUT / "circuit", OUT / "archives")
elapsed = run("prepare", "prepare", circuit, "--target-dir", OUT / "acir", "--pkp", OUT / "age.pkp", "--pkv", OUT / "age.pkv")
prove_time = run("valid", "prove", "--prover", OUT / "age.pkp", "--input", OUT / "inputs/valid.toml", "--out", OUT / "valid.np")
run("verify", "verify", "--verifier", OUT / "age.pkv", "--proof", OUT / "valid.np")
for name in cases:
    if name != "valid":
        run(name, "prove", "--prover", OUT / "age.pkp", "--input", OUT / "inputs" / (name+".toml"), "--out", OUT / "rejected.np", reject=True)
run("public-inputs", "show-inputs", OUT / "age.pkv", OUT / "valid.np")

# Exercise the same hash/date source with independent Python reference values.
# Separate small circuits keep these edge tests out of the shipping age circuit.
helpers = OUT / "helpers"
for name in ["hash", "date"]:
    folder = helpers / name
    (folder / "src").mkdir(parents=True, exist_ok=True)
    (folder / "Nargo.toml").write_text(f'[package]\nname = "check_{name}"\ntype = "bin"\nauthors = []\ncompiler_version = ">=1.0.0"\n')
    shutil.copyfile(ROOT / f"circuits/jpki_age/src/{name}.nr", folder / f"src/{name}.nr")
(helpers / "hash/src/main.nr").write_text('''mod hash;
fn main(length: pub u32, high: pub u128, low: pub u128, message: [u8;128]) {
    let digest = hash::sha256_var(message,length);
    let mut h: Field = 0; let mut l: Field = 0;
    for i in 0..16 {h = h*256+(digest[i] as Field); l = l*256+(digest[i+16] as Field);}
    assert(h == high as Field); assert(l == low as Field);
}
''')
(helpers / "date/src/main.nr").write_text('''mod date;
fn main(reference: pub u64, dob: [u8;8]) {date::adult(dob,reference);}
''')
for name in ["hash", "date"]:
    run(name+"-prepare", "prepare", helpers / name, "--pkp", helpers / name / "check.pkp", "--pkv", helpers / name / "check.pkv")
message = bytes(range(128))
for length in [0, 1, 55, 56, 63, 64, 65, 98, 127, 128]:
    digest = sha256(message[:length]).digest()
    data = dict(length=length, high=int.from_bytes(digest[:16], "big"), low=int.from_bytes(digest[16:], "big"), message=list(message))
    module.write_toml(helpers / "hash/input.toml", data)
    run(f"hash-{length}", "prove", "--prover", helpers / "hash/check.pkp", "--input", helpers / "hash/input.toml", "--out", helpers / "hash/proof.np")
    run(f"hash-{length}-verify", "verify", "--verifier", helpers / "hash/check.pkv", "--proof", helpers / "hash/proof.np")
data["low"] ^= 1
module.write_toml(helpers / "hash/input.toml", data)
run("hash-wrong-digest", "prove", "--prover", helpers / "hash/check.pkp", "--input", helpers / "hash/input.toml", "--out", helpers / "hash/rejected.np", reject=True)
jst = timezone(timedelta(hours=9))
for name, dob, day, delta, reject in [
    ("birthday", "20060102", "2026-01-02", 0, False),
    ("before-birthday", "20060102", "2026-01-02", -1, True),
    ("leap-birthday", "20040229", "2024-02-29", 0, False),
    ("before-leap-birthday", "20040229", "2024-02-29", -1, True),
    ("invalid-calendar", "20060229", "2026-03-01", 0, True),
    ("unknown-calendar", "00000000", "2026-03-01", 0, True),
    ("century-leap", "20000229", "2020-02-29", 0, False),
    ("century-anniversary", "20800229", "2100-03-01", 0, False),
    ("before-century-anniversary", "20800229", "2100-03-01", -1, True),
]:
    reference = int(datetime.fromisoformat(day).replace(tzinfo=jst).timestamp())+delta
    module.write_toml(helpers / "date/input.toml", dict(reference=reference, dob=list(dob.encode("ascii"))))
    run("date-"+name, "prove", "--prover", helpers / "date/check.pkp", "--input", helpers / "date/input.toml", "--out", helpers / "date/proof.np", reject=reject)
    if not reject:
        run("date-"+name+"-verify", "verify", "--verifier", helpers / "date/check.pkv", "--proof", helpers / "date/proof.np")
manifest = {
    "backend": "ProveKit 1.0.1 hiding WHIR",
    "dependencyArchives": {name: CONFIG[name] for name in DEPENDENCIES}, "syntheticCredentialsOnly": True,
    "physicalCard": False, "mobileProof": False, "evmVerification": False,
    "validProofVerified": True, "invalidWitnessesRejected": len(cases)-1,
    "prepareSeconds": elapsed, "proveSeconds": prove_time,
    "hashReferenceCases": 10, "wrongHashRejected": True, "calendarBoundaryCases": 9,
    "sourceSHA256": {str(p.relative_to(ROOT)): sha256(p.read_bytes()).hexdigest()
                     for p in sorted((ROOT / "circuits/jpki_age").rglob("*")) if p.is_file() and (p.suffix == ".nr" or p.name == "Nargo.toml")},
}
(OUT / "acceptance.json").write_text(json.dumps(manifest, indent=2)+"\n")
