"""Validate reviewed PUBLIC age setup; never accepts identity or wallet input."""
from hashlib import sha256
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / '.build/age-proof-engine'


def digest_file(path):
    digest = sha256()
    with path.open('rb') as source:
        while chunk := source.read(4 * 1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def validate_statement(actual, recorded, expected_hash):
    # Older reviewed setup records included these non-statement build/doc files.
    # Authenticate the COMPLETE original record against its reviewed pin first;
    # then compare every current source file. Never read paths from the record.
    record_hash = sha256(json.dumps(recorded, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    assert record_hash == expected_hash, 'Unreviewed statement record'
    historical = {'circuits/jpki_age/.gitignore', 'circuits/jpki_age/README.md',
                  'circuits/jpki_age/target/mate_jpki_age.json'}
    statement = {name: digest for name, digest in recorded.items() if name not in historical}
    assert actual == statement, 'Circuit changed; regenerate and review setup'


def checked_public_setup():
    pins = json.loads((ROOT / 'config/age-runtime-pins.json').read_text())
    provenance = json.loads((BASE / 'artifacts/provenance.json').read_text())
    assert provenance['sameWitnessCommitmentsDiffer'] is True
    assert pins['hidingPatchSHA256'] == provenance['hidingPatchSHA256']
    assert pins['hidingPatchSHA256'] == digest_file(ROOT / 'patches/provekit-groth16-hiding.patch')
    actual = {str(p.relative_to(ROOT)): digest_file(p) for p in sorted((ROOT / 'circuits/jpki_age').rglob('*'))
              if p.is_file() and (p.suffix == '.nr' or p.name == 'Nargo.toml')}
    validate_statement(actual, provenance['circuitSHA256'], pins['statementSHA256'])
    for file, pin in [('age.pkp', 'proverSHA256'), ('age.pkv', 'verifierSHA256')]:
        assert digest_file(BASE / 'artifacts' / file) == pins[pin], 'Unreviewed public setup'
    return pins
