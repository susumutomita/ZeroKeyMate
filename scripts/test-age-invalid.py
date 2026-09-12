"""Reject synthetic invalid witnesses with the actual masked Groth16 backend."""
from pathlib import Path
import importlib.util
import json
import os
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / ".build/age-proof-engine"
OUT = BASE / "artifacts"
CLI = BASE / "target/release/provekit-cli"
provenance = json.loads((OUT / "provenance.json").read_text())
assert provenance["sameWitnessCommitmentsDiffer"] is True
spec = importlib.util.spec_from_file_location("fixtures", ROOT / "scripts/jpki-age-fixtures.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
cases = module.fixtures(OUT / "inputs")
rejected = []
for name in cases:
    if name == "valid":
        continue
    with (BASE / ("reject-" + name + ".log")).open("w") as log:
        result = subprocess.run([str(CLI), "prove", "--prover", str(OUT / "age.pkp"),
                                 "--input", str(OUT / "inputs" / (name + ".toml")),
                                 "--out", str(OUT / "rejected.np")], cwd=ROOT,
                                env={**os.environ, "RAYON_NUM_THREADS": "2"}, stdout=log, stderr=log)
    plain = re.sub(r"\x1b\[[0-9;]*m", "", (BASE / ("reject-" + name + ".log")).read_text())
    assert result.returncode != 0, "Invalid witness accepted: " + name
    assert "bug:" not in plain and "panicked at" not in plain, "Runtime fault: " + name
    assert "While proving Noir program statement" in plain, "Not a constraint rejection: " + name
    assert "Failed assertion" in plain or "Failed to solve program" in plain, "Unexpected rejection: " + name
    rejected.append(name)
    print("Rejected " + name, flush=True)
(OUT / "invalid-acceptance.json").write_text(json.dumps({
    "syntheticOnly": True, "backend": "masked Groth16", "rejected": rejected,
    "hidingPatchSHA256": provenance["hidingPatchSHA256"],
    "circuitSHA256": provenance["circuitSHA256"],
}, indent=2) + "\n")
