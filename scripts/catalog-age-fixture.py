"""Fresh synthetic credential for a local-EVM order; never accepts or saves keys."""
from datetime import datetime, timezone
from hashlib import sha256
from pathlib import Path
import json
import sys
from cryptography import x509
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import rsa, padding
from cryptography.x509.oid import NameOID, ObjectIdentifier

root = Path(__file__).resolve().parents[1]
out = Path(sys.argv[1]).resolve()
assert out.is_relative_to(root / '.build')
out.mkdir(parents=True, exist_ok=True)
issuer = rsa.generate_private_key(public_exponent=65537, key_size=2048)
card = rsa.generate_private_key(public_exponent=65537, key_size=2048)
issuer_n = issuer.public_key().public_numbers().n
card_n = card.public_key().public_numbers().n
issuer_bytes = issuer_n.to_bytes(256, 'big')
root_hash = sha256(issuer_bytes).digest()
print(json.dumps({'syntheticRoot': '0x' + root_hash.hex()}), flush=True)
# The parent deploys an explicitly synthetic trust gate, then supplies its local
# order. Only invented identities and newly generated in-memory keys are used.
request = json.loads(sys.stdin.readline())
assert request['chainId'] == 31337
order = bytes.fromhex(request['orderHash'].removeprefix('0x'))
nonce = bytes.fromhex(request['nonce'].removeprefix('0x'))
assert len(order) == len(nonce) == 32
reference = int(request['referenceTime'])
expires = int(request['expiresAt'])
assert expires == reference + 900
name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'Synthetic catalogue test - not J-LIS')])
certificate = (x509.CertificateBuilder().subject_name(name).issuer_name(name)
    .public_key(card.public_key()).serial_number(2)
    .not_valid_before(datetime(2025, 1, 1, tzinfo=timezone.utc))
    .not_valid_after(datetime(2030, 1, 1, tzinfo=timezone.utc))
    .add_extension(x509.KeyUsage(True, True, False, False, False, False, False, False, False), critical=True)
    .add_extension(x509.SubjectAlternativeName([x509.OtherName(ObjectIdentifier('1.2.392.200149.8.5.5.4'), b'\x0c\x09419900102')]), False)
    .add_extension(x509.CertificatePolicies([x509.PolicyInformation(ObjectIdentifier('1.2.392.200149.8.5.1.1.20'), ['http://www.jpki.go.jp/cps.html'])]), critical=True)
    .sign(issuer, hashes.SHA256()))
tbs = certificate.tbs_certificate_bytes
assert len(tbs) <= 2048
values = {}
for field, data in [('order', order), ('nonce', nonce), ('root', root_hash)]:
    values[field + '_high'] = int.from_bytes(data[:16], 'big')
    values[field + '_low'] = int.from_bytes(data[16:], 'big')
values.update(reference_time=reference, expires_at=expires,
    tbs=list(tbs) + [0] * (2048-len(tbs)), tbs_length=len(tbs),
    certificate_signature=list(certificate.signature), root_modulus=list(issuer_bytes),
    root_redc=list(((1 << 4102)//issuer_n).to_bytes(257, 'big')),
    card_redc=list(((1 << 4102)//card_n).to_bytes(257, 'big')),
    card_signature=list(card.sign(b'ZeroKeyMate age authentication v1\0'+order+nonce, padding.PKCS1v15(), hashes.SHA256())))
def encode(value):
    return '"'+str(value)+'"' if isinstance(value, int) and value > 2**63-1 else str(value)
(out / 'input.toml').write_text(''.join(f'{key} = {encode(value)}\n' for key, value in values.items()))
print('synthetic witness ready', flush=True)
