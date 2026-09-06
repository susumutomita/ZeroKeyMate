#!/usr/bin/env python3
"""Static source audit only. Does not execute app, contracts, tests or deploy scripts."""
import ast
import json
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[1]
required = [
    'mate', '.env.example', 'LICENSE', 'apps/ios/project.yml',
    'apps/ios/ZeroKeyMate/ZeroKeyMateApp.swift', 'apps/ios/ZeroKeyMate/ProofService.swift',
    'apps/ios/ZeroKeyMate/WalletService.swift', 'apps/ios/ZeroKeyMate/PrivateFiles.swift',
    'services/api/server.mjs', 'services/api/executor.mjs', 'services/api/chain.mjs',
    'services/api/discovery.mjs', 'services/api/names.mjs', 'services/provider/server.mjs',
    'services/verifier/src/main.rs', 'contracts/src/MateVault.sol', 'contracts/src/MateNaming.sol',
    'circuits/mandate/src/main.nr', 'scripts/build-proofs.sh', 'scripts/build-native-runtime.sh',
    'scripts/setup-sepolia.mjs', 'scripts/register-provider.mjs',
]
errors = [f'Missing source: {name}' for name in required if not (root / name).is_file()]
files = [p for p in root.rglob('*') if p.is_file() and not any(
    part in {'.git', '.build', '.tools', 'node_modules', '.data', '.provider-data', 'DerivedData', 'Generated'}
    for part in p.relative_to(root).parts)]
for path in files:
    if path.suffix not in {'.mjs', '.py', '.json'}:
        continue
    try:
        text = path.read_text()
        if path.suffix == '.json':
            json.loads(text)
        elif path.suffix == '.py':
            ast.parse(text, filename=str(path))
        else:
            for match in re.finditer(r'(?:from\s*|import\s*\()\s*[\'"]([.][.\w/\-]+\.mjs)[\'"]', text):
                target = (path.parent / match[1]).resolve()
                if not target.is_relative_to(root) or not target.is_file():
                    errors.append(f'{path.relative_to(root)}: unresolved local import {match[1]}')
    except (ValueError, SyntaxError, UnicodeError) as error:
        errors.append(f'{path.relative_to(root)}: {error}')
# Report source wiring without pretending it establishes cryptographic or device behavior.
report = {'scope': 'static-file-and-import-integrity', 'filesExamined': len(files),
          'errors': errors, 'runtimeExecuted': False, 'releaseVerified': False}
print(json.dumps(report, ensure_ascii=False, indent=2))
sys.exit(bool(errors))
