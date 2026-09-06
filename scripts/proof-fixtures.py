#!/usr/bin/env python3
"""Public test vectors only. Never load a real user's policy or signing key."""
import hashlib
import json
import pathlib
import sys

root = pathlib.Path(__file__).resolve().parents[1]
out = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else root / '.build' / 'proofs'
out.mkdir(parents=True, exist_ok=True)
budget, spent, amount, service, services = 5_000_000, 0, 3_000_000, 0, 3
salt = bytes(range(32))
context = (b'ZKM-ACT1' + (11155111).to_bytes(8, 'big') + bytes.fromhex('11' * 20)
           + bytes.fromhex('22' * 32) + bytes.fromhex('33' * 20) + bytes.fromhex('44' * 32)
           + (2_000_000_000).to_bytes(8, 'big') + hashlib.sha256(b'Hello, Mate.').digest())
assert len(context) == 160
policy_hash = hashlib.sha256(b'ZKM-POL1' + budget.to_bytes(8, 'big') + bytes([services]) + salt).digest()
action_hash = hashlib.sha256(context + spent.to_bytes(8, 'big') + amount.to_bytes(8, 'big') + bytes([service])).digest()
values = dict(policy_hash=list(policy_hash), action_hash=list(action_hash), spent=str(spent),
              amount=str(amount), service=str(service), budget=str(budget), services=str(services),
              salt=list(salt), context=list(context))

def toml(v):
    return '\n'.join(f'{k} = {json.dumps(x)}' for k, x in v.items()) + '\n'

(out / 'valid.toml').write_text(toml(values))
(out / 'valid.json').write_text(json.dumps(values))
for name, edits in {
    'over-budget': {'budget': str(amount - 1)},
    'zero-amount': {'amount': '0'},
    'spent-over-budget': {'spent': str(budget + 1)},
    'forbidden-service': {'service': '2'},
    'changed-commitment': {'policy_hash': [0] * 32},
    'changed-action': {'action_hash': [0] * 32},
}.items():
    (out / f'{name}.toml').write_text(toml(values | edits))
(out / 'statement.json').write_text(json.dumps({
    'policyHash': '0x' + policy_hash.hex(), 'actionHash': '0x' + action_hash.hex(),
    'spent': str(spent), 'amount': str(amount), 'service': service,
}))
print(json.dumps({'policyHash': policy_hash.hex(), 'actionHash': action_hash.hex(), 'contextBytes': len(context)}))
