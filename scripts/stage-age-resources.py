"""Stage only the pinned PUBLIC test setup for an unsigned app build."""
from hashlib import sha256
from pathlib import Path
import json
import shutil

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / ".build/age-proof-engine"
pins = json.loads((ROOT / "config/age-runtime-pins.json").read_text())
provenance = json.loads((BASE / "artifacts/provenance.json").read_text())
acceptance = json.loads((BASE / "artifacts/local-acceptance.json").read_text())
assert provenance["sameWitnessCommitmentsDiffer"] and acceptance["validProofAccepted"]
assert pins["hidingPatchSHA256"] == provenance["hidingPatchSHA256"]
actual_sources = {str(p.relative_to(ROOT)): sha256(p.read_bytes()).hexdigest()
                  for p in sorted((ROOT / "circuits/jpki_age").rglob("*"))
                  if p.is_file() and (p.suffix == ".nr" or p.name == "Nargo.toml")}
assert actual_sources == provenance["circuitSHA256"], "Circuit changed; regenerate and review setup"
assert pins["statementSHA256"] == sha256(json.dumps(provenance["circuitSHA256"], sort_keys=True, separators=(",", ":")).encode()).hexdigest()
bundle = BASE / "bundle"
bundle.mkdir(exist_ok=True)
for file, pin in [("age.pkp", "proverSHA256"), ("age.pkv", "verifierSHA256")]:
    source = BASE / "artifacts" / file
    with source.open("rb") as stream:
        digest = sha256()
        while chunk := stream.read(4 * 1024 * 1024):
            digest.update(chunk)
    assert digest.hexdigest() == pins[pin], "Regenerated setup requires review and new app/contract pins"
    shutil.copyfile(source, bundle / file)
(bundle / "age-manifest.json").write_text(json.dumps(pins, indent=2) + "\n")
link = ROOT / "apps/ios/ZeroKeyMate/Resources/AgeProof"
if link.is_symlink():
    link.unlink()
assert not link.exists(), "Refusing to replace non-generated resources"
link.symlink_to(bundle, target_is_directory=True)
print("Staged public test parameters. No witness, certificate, PIN or private key included.")
