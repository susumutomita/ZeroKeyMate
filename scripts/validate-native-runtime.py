#!/usr/bin/env python3
"""Check pinned public source and native artifact integrity, without loading the app."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
root = Path(__file__).resolve().parents[1]
try:
    dependency = root / '.tools/verity'
    framework = dependency / 'output/Verity.xcframework'
    manifest = json.loads((framework / 'mate-runtime.json').read_text())
    expected = {'verityRevision': 'eb4bcb38be3ee7ecf36b06b06a9a98b6e204f97d',
                'provekitRevision': '4e011438c813ba2fb159e080879c41b0ab564053',
                'rustToolchain': 'nightly-2026-03-04'}
    if any(manifest.get(key) != value for key, value in expected.items()):
        raise ValueError('Unexpected native runtime provenance')
    revision = subprocess.check_output(['git', '-C', str(dependency), 'rev-parse', 'HEAD'], text=True).strip()
    if revision != expected['verityRevision']:
        raise ValueError('Unexpected Swift SDK revision')
    subprocess.run(['git', '-C', str(dependency), 'diff', '--exit-code', '--quiet'], check=True)
    files = manifest['libraries']
    if len(files) != 2:
        raise ValueError('Both iOS device and arm64 Simulator runtimes are required')
    for filename, checksum in files.items():
        path = (framework / filename).resolve()
        if not path.is_relative_to(framework.resolve()) or path.suffix != '.a':
            raise ValueError('Invalid runtime file path')
        if hashlib.sha256(path.read_bytes()).hexdigest() != checksum:
            raise ValueError('Native runtime checksum mismatch')
    print('Native ProveKit source and artifact checksums match the pinned provenance.')
except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
    print(str(error), file=sys.stderr)
    sys.exit(1)
