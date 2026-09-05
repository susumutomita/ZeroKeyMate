#!/usr/bin/env python3
"""Verify the native bundle's public setup artifacts; no private witnesses are read."""
import hashlib
import json
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
directory = root / 'apps/ios/ZeroKeyMate/Resources/Proofs'
try:
    manifest = json.loads((directory / 'manifest.json').read_text())
    expected = {'system': 'ProveKit', 'version': '1.0.1', 'circuit': 'mate_policy', 'hash': 'skyscraper'}
    if any(manifest.get(key) != value for key, value in expected.items()):
        raise ValueError('Unexpected proof system or circuit manifest')
    for name in ['mate_policy.pkp', 'mate_policy.pkv']:
        data = (directory / name).read_bytes()
        if not data or hashlib.sha256(data).hexdigest() != manifest['files'].get(name):
            raise ValueError(f'Artifact integrity check failed: {name}')
    print('ProveKit setup artifacts match the native circuit manifest.')
except (OSError, ValueError, KeyError, TypeError) as error:
    print(str(error), file=sys.stderr)
    sys.exit(1)
