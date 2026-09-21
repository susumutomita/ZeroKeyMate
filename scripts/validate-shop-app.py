#!/usr/bin/env python3
"""Reject incomplete debug shop bundles before installation; read public assets only."""
from hashlib import sha256
from pathlib import Path
import json
import plistlib
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def defined_symbols(binary):
    result = subprocess.run(['nm', '-gU', str(binary)], check=True, capture_output=True, text=True)
    return {line.split()[-1] for line in result.stdout.splitlines() if line.split()}


def validate(app, pins, symbols=defined_symbols):
    if not (app / 'ShopConnection.json').exists():
        return False  # A companion-only development build need not ship a shop.
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != 'com.zerokeymate.companion' or info.get('CFBundleExecutable') != 'ZeroKeyMate':
        raise ValueError('Unexpected shop application identity')
    config = json.loads((app / 'Configuration.json').read_text())
    if config.get('chainID') != 5042002 or not config.get('privyAppID') or not config.get('privyClientID'):
        raise ValueError('Shop bundle requires Arc Testnet and the public Privy application IDs')
    for filename, constant in [('age.pkp', 'proverSHA256'), ('age.pkv', 'verifierSHA256')]:
        matches = re.findall(r'static let ' + constant + r' = "([0-9a-f]{64})"', pins)
        if len(matches) != 1:
            raise ValueError('Missing or ambiguous public age-proof pin')
        artifact = app / filename
        if not artifact.is_file():
            raise ValueError('Shop bundle is missing its public age-proof setup: ' + filename)
        with artifact.open('rb') as stream:
            digest = sha256()
            for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b''):
                digest.update(chunk)
        if digest.hexdigest() != matches[0]:
            raise ValueError('Shop bundle age-proof setup does not match the installed contract pins: ' + filename)
    exported = set()
    for filename in ['ZeroKeyMate', 'ZeroKeyMate.debug.dylib']:
        binary = app / filename
        if binary.is_file():
            exported.update(symbols(binary))
    if not {'_mate_age_prove_measured', '_mate_age_keccak256'} <= exported:
        raise ValueError('Shop bundle is missing the current native age-proof runtime; do not install this build')
    return True


if __name__ == '__main__':
    try:
        if len(sys.argv) != 2:
            raise ValueError('Usage: validate-shop-app.py PATH_TO_DEBUG_APP')
        complete = validate(Path(sys.argv[1]), (ROOT / 'apps/ios/ZeroKeyMate/AgeProofPins.swift').read_text())
        print('Shop public setup and native runtime are present.' if complete else 'Companion-only build; no shop connection bundled.')
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
