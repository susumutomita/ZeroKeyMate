"""Stage only the pinned PUBLIC test setup for an unsigned app build."""
from age_artifacts import ROOT, BASE, checked_public_setup
import json
import shutil

pins = checked_public_setup()
acceptance = json.loads((BASE / "artifacts/local-acceptance.json").read_text())
assert acceptance["validProofAccepted"] is True
bundle = BASE / "bundle"
bundle.mkdir(exist_ok=True)
for file in ["age.pkp", "age.pkv"]:
    source = BASE / "artifacts" / file
    shutil.copyfile(source, bundle / file)
(bundle / "age-manifest.json").write_text(json.dumps(pins, indent=2) + "\n")
link = ROOT / "apps/ios/ZeroKeyMate/Resources/AgeProof"
if link.is_symlink():
    link.unlink()
assert not link.exists(), "Refusing to replace non-generated resources"
link.symlink_to(bundle, target_is_directory=True)
print("Staged public test parameters. No witness, certificate, PIN or private key included.")
