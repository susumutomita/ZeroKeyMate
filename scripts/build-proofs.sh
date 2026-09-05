#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$ROOT/.tools"
OUT="$ROOT/.build/proofs"
export PATH="$TOOLS/bin:$HOME/.cargo/bin:$PATH"
mkdir -p "$TOOLS" "$OUT"
command -v rustup >/dev/null || { echo 'Rust is required: install rustup, then run this command again.' >&2; exit 1; }
rustup toolchain install nightly-2026-03-04 --profile minimal
if [[ ! -x "$TOOLS/bin/provekit-cli" ]]; then
  cargo +nightly-2026-03-04 install provekit-cli --version 1.0.1 --locked --root "$TOOLS"
fi
python3 "$ROOT/scripts/proof-fixtures.py" "$OUT"
provekit-cli prepare "$ROOT/circuits/mandate" --pkp "$OUT/mate_policy.pkp" --pkv "$OUT/mate_policy.pkv"
provekit-cli prove --prover "$OUT/mate_policy.pkp" --input "$OUT/valid.toml" --out "$OUT/valid.np"
provekit-cli verify --verifier "$OUT/mate_policy.pkv" --proof "$OUT/valid.np"
for test in over-budget zero-amount spent-over-budget forbidden-service changed-commitment changed-action; do
  if provekit-cli prove --prover "$OUT/mate_policy.pkp" --input "$OUT/$test.toml" --out "$OUT/rejected.np" >"$OUT/$test.log" 2>&1; then
    echo "ERROR: invalid witness accepted: $test" >&2; exit 1
  fi
  printf 'Rejected %s\n' "$test"
done
provekit-cli show-inputs "$OUT/mate_policy.pkv" "$OUT/valid.np" > "$OUT/public-inputs.txt"
python3 - "$OUT" <<'PY'
import hashlib, json, pathlib, sys
p = pathlib.Path(sys.argv[1])
manifest = {'system': 'ProveKit', 'version': '1.0.1', 'circuit': 'mate_policy', 'hash': 'skyscraper',
            'files': {n: hashlib.sha256((p/n).read_bytes()).hexdigest() for n in ['mate_policy.pkp','mate_policy.pkv']}}
(p/'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
PY
mkdir -p "$ROOT/apps/ios/ZeroKeyMate/Resources/Proofs"
cp "$OUT/mate_policy.pkp" "$OUT/mate_policy.pkv" "$OUT/manifest.json" "$ROOT/apps/ios/ZeroKeyMate/Resources/Proofs/"
