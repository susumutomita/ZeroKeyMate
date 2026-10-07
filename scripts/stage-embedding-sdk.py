#!/usr/bin/env python3
"""Stage only unmodified public Swift wrappers and verified iOS binaries.

Avoid Xcode downloading unused macOS binaries or Git LFS test assets. The
generated package changes packaging only; no runtime source is patched.
"""
import hashlib
import pathlib
import shutil
import subprocess
import zipfile

root = pathlib.Path(__file__).resolve().parents[1]
source = root / '.tools/litertlm'
revision = 'b2f686e2ed4718fb84ec398a61dd59ca0f0aff27'
assert subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip() == revision
subprocess.run(['git', '-C', str(source), 'diff', 'HEAD', '--exit-code', '--quiet'], check=True)
archive = root / '.tools/downloads/CLiteRTLM-0.18.0.xcframework.zip'
with archive.open('rb') as stream:
    assert hashlib.file_digest(stream, 'sha256').hexdigest() == 'd765b99592d4ec3d0c9e2bd69469454af06c834861340672da1891c0c121c347', 'Unexpected LiteRT-LM binary checksum'
staged = root / '.tools/litertlm-sdk'
staged.mkdir(parents=True, exist_ok=True)
wrapper = staged / 'swift'
wrapper.mkdir(exist_ok=True)
tracked = subprocess.check_output(['git', '-C', str(source), 'ls-files', 'swift/*.swift'], text=True).splitlines()
expected = {pathlib.PurePosixPath(p).name for p in tracked
            if len(pathlib.PurePosixPath(p).parts) == 2 and not p.endswith('Tests.swift')}
for path in wrapper.glob('*.swift'):
    if path.name not in expected:
        path.unlink()
for name in sorted(expected):
    shutil.copyfile(source / 'swift' / name, wrapper / name)
shutil.copyfile(source / 'LICENSE', staged / 'LICENSE')
with zipfile.ZipFile(archive) as zipped:
    assert all(pathlib.PurePosixPath(name).parts[0] == 'CLiteRTLM.xcframework' and '..' not in pathlib.PurePosixPath(name).parts for name in zipped.namelist())
    zipped.extractall(staged)
(staged / 'Package.swift').write_text('''// swift-tools-version: 5.9
// Generated packaging for the unmodified Apache-2.0 LiteRT-LM 0.18.0 wrapper.
import PackageDescription
let package = Package(name: "LiteRTLM", platforms: [.iOS(.v15)],
    products: [.library(name: "LiteRTLM", targets: ["LiteRTLM"])],
    targets: [
        .binaryTarget(name: "CLiteRTLM", path: "CLiteRTLM.xcframework"),
        .target(name: "LiteRTLM", dependencies: ["CLiteRTLM"], path: "swift")
    ])
''')
print('Staged pinned LiteRT-LM iOS SDK; no embedding weights were installed.')
