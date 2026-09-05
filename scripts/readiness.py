#!/usr/bin/env python3
"""Truthful product readiness report. Existence of configuration is not verification."""
import json
import os
from pathlib import Path
import platform
import shutil
import sys

root = Path(__file__).resolve().parents[1]
checks = {
    'native_host': platform.system() == 'Darwin' and platform.machine() == 'arm64',
    'xcode_command': shutil.which('xcodebuild') is not None,
    'privy_identifiers_in_environment': bool(os.getenv('PRIVY_APP_ID') and os.getenv('PRIVY_IOS_CLIENT_ID')),
    'graph_key_in_environment': bool(os.getenv('GRAPH_API_KEY')),
    'vault_address_in_environment': bool(os.getenv('MATE_VAULT_ADDRESS')),
    'ens_parent_in_environment': bool(os.getenv('ENS_PARENT_NAME')),
    'execution_server_source_present': (root / 'services/api/server.mjs').is_file(),
    'specialist_server_source_present': (root / 'services/provider/server.mjs').is_file(),
    'native_proof_resources_present': (root / 'apps/ios/ZeroKeyMate/Resources/Proofs/manifest.json').is_file(),
}
report = {
    'checks': checks,
    'readiness': 'not-release-verified',
    'requires_independent_evidence': [
        'Physical iPhone and Belkin tracking, consent and stop behavior',
        'Actual on-device speech and Foundation Models conversation',
        'Privy owner/agent wallet setup and signed transaction',
        'Live ENSv2 registration and resolution on Sepolia',
        'Live The Graph discovery used in a completed request',
        'On-device proof to verified, confirmed payment and actual specialist result',
        'Portrait/landscape visual review and accessibility acceptance',
    ],
    'note': 'No secrets are printed. Environment presence never counts as end-to-end verification.',
}
print(json.dumps(report, ensure_ascii=False, indent=2))
sys.exit(1)
