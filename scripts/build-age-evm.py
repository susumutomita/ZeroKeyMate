"""Reproduce the experimental direct Groth16 age proof, locally and with fake IDs.

Downloads only checksum-pinned public source. Generates single-party TEST setup
parameters. Never deploys, signs, reads .env/keys, contacts a card or starts payment.
The shipping iOS proof runtime is left untouched. Requires Rust nightly-2026-03-04,
Python cryptography 49.0.0, Node and Anvil (the latter only for test-age-evm.mjs).
"""
from age_sources import materialize, vendor_circuit
from hashlib import sha256
from pathlib import Path
import argparse
import importlib.util
import io
import json
import os
import platform
import shutil
import subprocess
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / ".build/age-proof-engine"
parser = argparse.ArgumentParser()
parser.add_argument("--artifacts", default=".build/age-proof-engine/artifacts")
OUT = (ROOT / parser.parse_args().artifacts).resolve()
assert OUT.is_relative_to(ROOT / ".build"), "Use an isolated local build artifact directory"
CONFIG = json.loads((ROOT / "config/age-proof-sources.json").read_text())
PATCH = ROOT / "patches/provekit-groth16-noir-directory.patch"
HIDING_PATCH = ROOT / "patches/provekit-groth16-hiding.patch"
BASE.mkdir(parents=True, exist_ok=True)
OUT.mkdir(parents=True, exist_ok=True)
env = {**os.environ, "CARGO_HOME": str(BASE / "cargo"), "CARGO_TARGET_DIR": str(BASE / "target"),
       "CARGO_BUILD_JOBS": "2", "RAYON_NUM_THREADS": "2", "RUSTUP_TOOLCHAIN": "nightly-2026-03-04",
       "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull, "GIT_TERMINAL_PROMPT": "0"}
toolchains = ROOT / ".tools/rustup/toolchains"
host = "aarch64-apple-darwin" if platform.system() == "Darwin" else "x86_64-unknown-linux-gnu"
bundled = toolchains / ("nightly-2026-03-04-" + host) / "bin"
cargo = str(bundled / "cargo") if (bundled / "cargo").exists() else "cargo"
if (bundled / "rustc").exists():
    env.update(RUSTC=str(bundled / "rustc"), RUSTDOC=str(bundled / "rustdoc"))


def run(name, args, cwd=ROOT):
    print(name, flush=True)
    with (BASE / (name + ".log")).open("w") as log:
        result = subprocess.run(list(map(str, args)), cwd=cwd, env=env, stdout=log, stderr=log)
    output = (BASE / (name + ".log")).read_text()
    assert result.returncode == 0 and "bug:" not in output and "panicked at" not in output, f"Failed {name}; inspect its synthetic-only log"


source = materialize("provekit", BASE, BASE / "provekit")
marker = source / ".mate-compiler-patch"
patch_hash = sha256(PATCH.read_bytes()).hexdigest()
if marker.exists():
    assert marker.read_text() == patch_hash, "Compiler patch changed; use a fresh isolated build directory"
else:
    run("compiler-patch", ["patch", "-p1", "-i", PATCH], cwd=source)
    marker.write_text(patch_hash)
hiding_marker = source / ".mate-hiding-patch"
hiding_hash = sha256(HIDING_PATCH.read_bytes()).hexdigest()
if hiding_marker.exists():
    assert hiding_marker.read_text() == hiding_hash, "Hiding patch changed; use a fresh isolated source directory"
else:
    run("hiding-patch", ["patch", "-p1", "-i", HIDING_PATCH], cwd=source)
    hiding_marker.write_text(hiding_hash)
run("engine-build", [cargo, "build", "--release", "--locked", "--no-default-features", "-p", "provekit-cli", "--manifest-path", source / "Cargo.toml"])
cli = BASE / "target/release/provekit-cli"
circuit = vendor_circuit(BASE / "circuit", BASE, beta19=True)
run("prepare", [cli, "prepare", circuit, "--backend", "groth16", "--mmap", "--pkp", OUT / "age.pkp", "--pkv", OUT / "age.pkv"])
spec = importlib.util.spec_from_file_location("fixtures", ROOT / "scripts/jpki-age-fixtures.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.fixtures(OUT / "inputs")
run("prove", [cli, "prove", "--prover", OUT / "age.pkp", "--input", OUT / "inputs/valid.toml", "--out", OUT / "valid.np"])
run("verify", [cli, "verify", "--verifier", OUT / "age.pkv", "--proof", OUT / "valid.np"])
run("template-patch", ["python3", ROOT / "scripts/patch-age-verifier.py", source / "provekit/groth16/contracts/ProvekitGroth16Verifier.sol", OUT / "template.sol"])
run("export-solidity", [cli, "export-solidity", "--pkv", OUT / "age.pkv", "--template", OUT / "template.sol", "--out", OUT / "Verifier.sol"])
run("export-proof", [cli, "export-evm-proof", "--proof", OUT / "valid.np", "--out-dir", OUT / "evm"])
# A new complete proof is not sufficient: compare the commitment specifically.
# Groth16's randomized A/B points could otherwise mask a deterministic C bug.
run("prove-again", [cli, "prove", "--prover", OUT / "age.pkp", "--input", OUT / "inputs/valid.toml", "--out", OUT / "second.np"])
run("verify-again", [cli, "verify", "--verifier", OUT / "age.pkv", "--proof", OUT / "second.np"])
run("export-again", [cli, "export-evm-proof", "--proof", OUT / "second.np", "--out-dir", OUT / "second-evm"])
first = bytes.fromhex((OUT / "evm/proof.hex").read_text().strip()[2:])
second = bytes.fromhex((OUT / "second-evm/proof.hex").read_text().strip()[2:])
assert len(first) == len(second) == 384 and first[256:320] != second[256:320], "Non-hiding deterministic commitment"
assert (OUT / "evm/inputs.txt").read_bytes() == (OUT / "second-evm/inputs.txt").read_bytes()
record = {"status": "experimental single-party test setup, not an iPhone runtime", "sourceArchives": CONFIG,
          "compilerPatchSHA256": patch_hash,
          "hidingPatchSHA256": hiding_hash, "sameWitnessCommitmentsDiffer": True,
          "circuitSHA256": {str(p.relative_to(ROOT)): sha256(p.read_bytes()).hexdigest() for p in sorted((ROOT / "circuits/jpki_age").rglob("*")) if p.is_file() and (p.suffix == ".nr" or p.name == "Nargo.toml")},
          "artifactSHA256": {name: sha256((OUT / name).read_bytes()).hexdigest() for name in ["age.pkp", "age.pkv", "Verifier.sol"]}}
(OUT / "provenance.json").write_text(json.dumps(record, indent=2)+"\n")
print(f"Built a synthetic local proof. Next: node scripts/test-age-evm.mjs {OUT.relative_to(ROOT)}")
