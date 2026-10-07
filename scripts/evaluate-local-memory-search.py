#!/usr/bin/env python3
"""Run real, offline Mac acceptance with explicitly supplied public artifacts.

First run MATE_EMBEDDING_PREVIEW=1 make setup-ios. Supply the pinned model and official macOS v0.18.0
ZIP yourself; this script performs no artifact download or app-data access.
"""
import argparse
import hashlib
import json
import pathlib
import shutil
import subprocess
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument('--model', type=pathlib.Path, required=True)
parser.add_argument('--runtime-zip', type=pathlib.Path, required=True)
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[1]
source = root / '.tools/litertlm'
assert subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip() == 'b2f686e2ed4718fb84ec398a61dd59ca0f0aff27'
subprocess.run(['git', '-C', str(source), 'diff', 'HEAD', '--exit-code', '--quiet'], check=True)
with args.runtime_zip.open('rb') as stream:
    assert hashlib.file_digest(stream, 'sha256').hexdigest() == '5f6ee68d95eeccb084c6e66d5ee47255e3020fa0fb29696dd0301ae26d6cfb4f'
staged = root / '.build/local-embedding-qa'
(staged / 'SDK').mkdir(parents=True, exist_ok=True)
(staged / 'Runner').mkdir(exist_ok=True)
for p in (source / 'swift').glob('*.swift'):
    if not p.name.endswith('Tests.swift'):
        shutil.copyfile(p, staged / 'SDK' / p.name)
shutil.copyfile(root / 'apps/ios/ZeroKeyMate/LocalEmbeddingRuntime.swift', staged / 'Runner/LocalEmbeddingRuntime.swift')
shutil.copyfile(root / 'scripts/evaluate-local-memory-search.swift', staged / 'Runner/Acceptance.swift')
with zipfile.ZipFile(args.runtime_zip) as archive:
    assert all('..' not in pathlib.PurePosixPath(name).parts and not name.startswith('/') for name in archive.namelist())
    archive.extractall(staged)
frameworks = list(staged.glob('*.xcframework'))
assert len(frameworks) == 1
(staged / 'Package.swift').write_text(f'''// swift-tools-version: 5.10
import PackageDescription
let package = Package(name: "LocalEmbeddingQA", platforms: [.macOS(.v14)],
    dependencies: [.package(path: {json.dumps(str(root))})],
    targets: [
        .binaryTarget(name: "CLiteRTLM", path: {json.dumps(frameworks[0].name)}),
        .target(name: "LiteRTLM", dependencies: ["CLiteRTLM"], path: "SDK"),
        .executableTarget(name: "LocalEmbeddingQA", dependencies: ["LiteRTLM", .product(name: "MateCore", package: {json.dumps(root.name.lower())})], path: "Runner", swiftSettings: [.define("MATE_EMBEDDING_PREVIEW")])
    ])
''')
subprocess.run(['swift', 'run', '--package-path', str(staged), '--cache-path', str(root / '.build/swift-cache'),
                '--scratch-path', str(root / '.build/local-embedding-qa-build'), 'LocalEmbeddingQA', str(args.model.resolve())], check=True)
