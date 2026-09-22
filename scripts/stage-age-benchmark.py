"""Stage only pinned PUBLIC WHIR keys; never reads cards, wallets or .env.

The normal age.pkp/pkv baseline must be staged separately using its existing
release pins. New setup files require explicit pin review, never silent trust.
"""
from pathlib import Path
from hashlib import file_digest, sha256
import argparse
import json
import shutil

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('whir_directory', type=Path)
args = parser.parse_args()
pins = json.loads((ROOT / 'config/age-benchmark-pins.json').read_text())
age = json.loads((ROOT / 'config/age-runtime-pins.json').read_text())
assert pins['syntheticOnly'] is True and pins['statementSHA256'] == age['statementSHA256']
assert pins['fixtureSHA256'] == sha256((ROOT / 'native/age-proof/src/benchmark-input.json').read_bytes()).hexdigest()
resources = ROOT / 'apps/ios/ZeroKeyMate/Resources'
paths = []
for ext in ['pkp', 'pkv']:
    source = args.whir_directory / ('age-whir.' + ext)
    with source.open('rb') as file:
        assert file_digest(file, 'sha256').hexdigest() == pins['whir'][ext + 'SHA256'], 'Unreviewed benchmark setup'
    paths.append((source, resources / ('age-benchmark-whir.' + ext)))
for source, destination in paths:
    shutil.copyfile(source, destination)
print('Staged pinned public synthetic benchmark keys. The purchase verifier is unchanged.')
