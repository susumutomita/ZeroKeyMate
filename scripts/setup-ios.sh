#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="$ROOT/.tools/bin:$PATH"
mkdir -p .tools/bin .tools/downloads
if [[ ! -x .tools/bin/xcodegen ]]; then
  curl -fLsS https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip -o .tools/downloads/xcodegen.zip
  python3 - <<'PY'
import hashlib, pathlib, zipfile
p=pathlib.Path('.tools/downloads/xcodegen.zip')
assert hashlib.sha256(p.read_bytes()).hexdigest()=='4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806'
with zipfile.ZipFile(p) as archive: archive.extractall('.tools/downloads/xcodegen')
PY
  cp .tools/downloads/xcodegen/xcodegen/bin/xcodegen .tools/bin/xcodegen
  chmod +x .tools/bin/xcodegen
fi
if [[ -x .tools/bin/xcodegen && ! -d .tools/share/xcodegen ]]; then
  cp -R .tools/downloads/xcodegen/xcodegen/share .tools/
fi
REV=eb4bcb38be3ee7ecf36b06b06a9a98b6e204f97d
if [[ ! -d .tools/verity ]]; then
  git init -q .tools/verity
  git -C .tools/verity remote add origin https://github.com/atheonxyz/verity.git
  git -C .tools/verity fetch --depth=1 origin "$REV"
  git -C .tools/verity checkout --detach -q FETCH_HEAD
fi
[[ "$(git -C .tools/verity rev-parse HEAD)" == "$REV" ]] || { echo 'Unexpected Verity source revision.' >&2; exit 1; }
git -C .tools/verity diff --exit-code --quiet

# Xcode's remote resolver requires Git LFS for this repository. No LFS test
# weights are needed by its Swift package. Keep pointer files and use only the
# unmodified wrapper and checksum-pinned release binaries from Package.swift.
LITERT_REV=b2f686e2ed4718fb84ec398a61dd59ca0f0aff27
if [[ ! -d .tools/litertlm ]]; then
  git init -q .tools/litertlm
  git -C .tools/litertlm remote add origin https://github.com/google-ai-edge/LiteRT-LM.git
  git -C .tools/litertlm fetch --depth=1 --filter=blob:none origin "$LITERT_REV"
  git -C .tools/litertlm sparse-checkout set --no-cone /Package.swift /LICENSE /swift/
  GIT_LFS_SKIP_SMUDGE=1 git -C .tools/litertlm -c filter.lfs.smudge= -c filter.lfs.required=false checkout --detach -q FETCH_HEAD
fi
[[ "$(git -C .tools/litertlm rev-parse HEAD)" == "$LITERT_REV" ]] || { echo 'Unexpected LiteRT-LM source revision.' >&2; exit 1; }
git -C .tools/litertlm diff --exit-code --quiet
if [[ ! -f .tools/downloads/CLiteRTLM-0.18.0.xcframework.zip ]]; then
  curl -fLsS --max-time 180 https://github.com/google-ai-edge/LiteRT-LM/releases/download/v0.18.0/CLiteRTLM.xcframework.zip -o .tools/downloads/CLiteRTLM-0.18.0.xcframework.zip.partial
  mv .tools/downloads/CLiteRTLM-0.18.0.xcframework.zip.partial .tools/downloads/CLiteRTLM-0.18.0.xcframework.zip
fi
python3 scripts/stage-embedding-sdk.py
