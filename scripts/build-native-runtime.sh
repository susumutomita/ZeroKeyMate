#!/usr/bin/env bash
# Build the upstream ProveKit FFI, not an older opaque release binary.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERITY_REV=eb4bcb38be3ee7ecf36b06b06a9a98b6e204f97d
PROVEKIT_REV=4e011438c813ba2fb159e080879c41b0ab564053
TOOLCHAIN=nightly-2026-03-04
[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || {
  echo 'The native proving runtime must be built on an Apple Silicon Mac.' >&2; exit 1;
}
command -v rustup >/dev/null || { echo 'Install rustup before building the native runtime.' >&2; exit 1; }
mkdir -p "$ROOT/.tools"
checkout() {
  local directory="$1" repository="$2" revision="$3"
  if [[ ! -d "$directory/.git" ]]; then
    [[ ! -e "$directory" ]] || { echo "Refusing to replace existing directory: $directory" >&2; exit 1; }
    git init -q "$directory"
    git -C "$directory" remote add origin "$repository"
    git -C "$directory" fetch --depth=1 origin "$revision"
    git -C "$directory" checkout --detach -q FETCH_HEAD
  fi
  [[ "$(git -C "$directory" rev-parse HEAD)" == "$revision" ]] || { echo 'Unexpected dependency revision.' >&2; exit 1; }
  git -C "$directory" diff --exit-code --quiet
}
checkout "$ROOT/.tools/verity" https://github.com/atheonxyz/verity.git "$VERITY_REV"
checkout "$ROOT/.tools/provekit-source" https://github.com/worldfnd/provekit.git "$PROVEKIT_REV"
rustup toolchain install "$TOOLCHAIN" --profile minimal
export RUSTUP_TOOLCHAIN="$TOOLCHAIN"
rustup target add aarch64-apple-ios aarch64-apple-ios-sim
export CARGO_PROFILE=release-fast
export PROVEKIT_PROFILE=release-fast
export IPHONEOS_DEPLOYMENT_TARGET=17.0
# Resolve exactly the checked-in lockfile before the upstream build script runs.
cargo fetch --locked --manifest-path "$ROOT/.tools/provekit-source/Cargo.toml"
bash "$ROOT/.tools/verity/core/build/build-ios.sh" "$ROOT/.tools/provekit-source" --backends provekit
python3 - "$ROOT" "$VERITY_REV" "$PROVEKIT_REV" "$TOOLCHAIN" <<'PY'
import hashlib,json,pathlib,sys
root=pathlib.Path(sys.argv[1]);framework=root/'.tools/verity/output/Verity.xcframework'
files={str(p.relative_to(framework)):hashlib.sha256(p.read_bytes()).hexdigest() for p in framework.rglob('*.a')}
assert len(files)==2, 'Both native device and native Simulator libraries are required'
(framework/'mate-runtime.json').write_text(json.dumps({'verityRevision':sys.argv[2],
    'provekitRevision':sys.argv[3],'rustToolchain':sys.argv[4],'libraries':files},indent=2)+'\n')
PY
printf '%s\n' 'Built upstream native ProveKit for iOS and Apple Silicon Simulator.'
