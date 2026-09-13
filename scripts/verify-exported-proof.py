#!/usr/bin/env python3
"""Independently verify an exported proof; never infer where it was generated."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]


def digest(data):
    return hashlib.sha256(data).hexdigest()


def verify_export(proof_path, resources, binary, report_path, timeout=120):
    # Snapshot inputs so a concurrently replaced export cannot change the evidence.
    proof = Path(proof_path).read_bytes()
    if not 0 < len(proof) <= 8 * 1024 * 1024:
        raise ValueError('Proof must contain 1 to 8388608 bytes')
    resources = Path(resources)
    manifest_bytes = (resources / 'manifest.json').read_bytes()
    manifest = json.loads(manifest_bytes)
    expected = {'system': 'ProveKit', 'version': '1.0.1', 'circuit': 'mate_policy', 'hash': 'skyscraper'}
    if any(manifest.get(k) != v for k, v in expected.items()):
        raise ValueError('Unexpected circuit manifest')
    key = (resources / 'mate_policy.pkv').read_bytes()
    if not key or digest(key) != manifest['files'].get('mate_policy.pkv'):
        raise ValueError('Verifier key does not match the supplied build manifest')
    binary = Path(binary).resolve(strict=True)
    binary_hash = digest(binary.read_bytes())
    with tempfile.TemporaryDirectory(prefix='mate-export-') as temporary:
        directory = Path(temporary)
        key_path = directory / 'mate_policy.pkv'
        proof_copy = directory / 'original.np'
        changed_path = directory / 'modified.np'
        key_path.write_bytes(key)
        proof_copy.write_bytes(proof)
        changed = bytearray(proof)
        changed[len(changed) // 2] ^= 1
        changed_path.write_bytes(changed)

        def check(path):
            # Output can include public statements; keep it out of the saved report/log.
            return subprocess.run([str(binary), str(key_path), str(path)],
                                  capture_output=True, timeout=timeout, check=False)

        original = check(proof_copy)
        if original.returncode != 0:
            raise ValueError('Original proof was not accepted; no acceptance report written')
        # A crash, loader failure or unrelated exit is not cryptographic rejection.
        modified = check(changed_path)
        if modified.returncode != 1 or not modified.stderr.startswith(
                (b'cryptographic verification failed', b'decode proof:')):
            raise ValueError('Modified proof rejection was not confirmed; no acceptance report written')
        # Repeat the original to distinguish a persistent verifier/environment failure.
        if check(proof_copy).returncode != 0:
            raise ValueError('Original proof recheck failed; no acceptance report written')
    report = {
        'schema': 'mate-export-verification-v1',
        'verifiedAt': datetime.now(timezone.utc).isoformat(),
        'proofSHA256': digest(proof), 'proofBytes': len(proof),
        'verifierKeySHA256': digest(key), 'manifestSHA256': digest(manifest_bytes),
        'verifierBinarySHA256': binary_hash,
        'originalAccepted': True, 'modifiedRejected': True, 'originalRecheckAccepted': True,
        'modifiedRejection': 'decode' if modified.stderr.startswith(b'decode proof:') else 'cryptographic',
        'deviceOrigin': 'not-verified', 'offlineGeneration': 'not-verified',
        'devicePerformance': 'not-measured',
    }
    # Never overwrite a previous acceptance record or follow an existing symlink.
    fd = os.open(report_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as output:
        json.dump(report, output, indent=2)
        output.write('\n')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('proof', type=Path)
    parser.add_argument('--resources', type=Path, default=ROOT / 'apps/ios/ZeroKeyMate/Resources/Proofs')
    parser.add_argument('--verifier', type=Path, default=ROOT / 'services/verifier/target/release/mate-verify')
    parser.add_argument('--report', type=Path, required=True, help='New local JSON file; never overwritten')
    args = parser.parse_args()
    try:
        verify_export(args.proof, args.resources, args.verifier, args.report)
    except (OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired):
        parser.exit(1, 'Verification incomplete. Check the proof, matching build resources, verifier binary and new report path. No acceptance is claimed.\n')
    print('Original accepted, modified copy rejected, original recheck accepted. Local report saved.')
    print('Device origin, offline generation and device performance still require separate evidence.')


if __name__ == '__main__':
    main()
