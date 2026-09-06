#!/usr/bin/env python3
import hashlib,json,pathlib
root=pathlib.Path(__file__).resolve().parents[1]
framework=root/'.tools/verity/output/Verity.xcframework'
manifest=json.loads((framework/'mate-runtime.json').read_text())
assert manifest['verityRevision']=='eb4bcb38be3ee7ecf36b06b06a9a98b6e204f97d'
assert manifest['provekitRevision']=='4e011438c813ba2fb159e080879c41b0ab564053'
assert set(manifest['libraries'])=={'ios-arm64/libverity.a','ios-arm64-simulator/libverity.a'}
for name,expected in manifest['libraries'].items():
    assert hashlib.sha256((framework/name).read_bytes()).hexdigest()==expected, name
print('Native runtime integrity checked for both Apple targets.')
