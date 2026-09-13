"""Generate synthetic certificates/signature for offline tests; never save keys.

Requires the Python cryptography library. These are NOT government credentials.
All people, addresses and dates are invented. No card, network or existing key
is accessed. Tests verify these under the synthetic root through an internal API;
the public verifier rejects them against the bundled J-LIS roots.
"""
from datetime import datetime, timezone
from pathlib import Path
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa, padding
from cryptography.x509.oid import NameOID, ObjectIdentifier
import argparse
import json
from hashlib import sha256

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--out', type=Path)
out = parser.parse_args().out or Path(__file__).resolve().parents[1] / "Tests/MateCoreTests/Fixtures/JPKI"
out.mkdir(parents=True, exist_ok=True)
root_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
card_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
root_name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "Synthetic Mate test root - not J-LIS")])
before = datetime(2025, 1, 1, tzinfo=timezone.utc)
after = datetime(2030, 1, 1, tzinfo=timezone.utc)
root = (x509.CertificateBuilder().subject_name(root_name).issuer_name(root_name)
        .public_key(root_key.public_key()).serial_number(1).not_valid_before(before).not_valid_after(after)
        .add_extension(x509.BasicConstraints(ca=True, path_length=0), critical=True)
        .add_extension(x509.KeyUsage(False, False, False, False, False, True, True, False, False), critical=True)
        .sign(root_key, hashes.SHA256()))
leaf_base = (x509.CertificateBuilder()
             .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "Synthetic card, no real identity")]))
             .issuer_name(root_name).public_key(card_key.public_key()).serial_number(2)
             .not_valid_before(before).not_valid_after(after)
             .add_extension(x509.KeyUsage(True, True, False, False, False, False, False, False, False), critical=True))

def leaf(date, extra_names=(), policy='1.2.392.200149.8.5.1.1.20', unknown_critical=False):
    value = date.encode("ascii")
    dob = x509.OtherName(ObjectIdentifier("1.2.392.200149.8.5.5.4"), bytes([12, len(value)]) + value)
    builder = leaf_base.add_extension(x509.SubjectAlternativeName([dob, *extra_names]), False)
    if policy:
        builder = builder.add_extension(x509.CertificatePolicies([
            x509.PolicyInformation(ObjectIdentifier(policy), ['http://www.jpki.go.jp/cps.html'])
        ]), critical=True)
    if unknown_critical:
        builder = builder.add_extension(x509.UnrecognizedExtension(ObjectIdentifier('1.2.3.4.5'), b'\x05\x00'), critical=True)
    return builder.sign(root_key, hashes.SHA256())

for name, certificate in {
    "root": root, "card": leaf("419900102"), "unknown-date": leaf("400000000"),
    "duplicate-date": leaf("419900102", [x509.OtherName(ObjectIdentifier("1.2.392.200149.8.5.5.4"), b"\x0c\x09419910203")]),
    "underage": leaf("520200102"), "missing-policy": leaf("419900102", policy=None),
    "wrong-policy": leaf("419900102", policy='1.2.392.200149.8.5.1.1.30'),
    "unknown-critical": leaf("419900102", unknown_critical=True)
}.items():
    (out / (name + ".der")).write_bytes(certificate.public_bytes(serialization.Encoding.DER))
message = b"ZeroKeyMate age authentication v1\0" + bytes([1]) * 32 + bytes([2]) * 32
(out / "card-signature.bin").write_bytes(card_key.sign(message, padding.PKCS1v15(), hashes.SHA256()))

# Independent reference for the Swift witness builder, from the same fake
# certificates. Private RSA keys are never serialized or printed.
card = x509.load_der_x509_certificate((out / 'card.der').read_bytes())
root_n = root.public_key().public_numbers().n
card_n = card.public_key().public_numbers().n
root_hash = sha256(root_n.to_bytes(256, 'big')).digest()
public = [str(int.from_bytes(raw[part:part+16], 'big'))
          for raw in [bytes([1])*32, bytes([2])*32, root_hash] for part in [0, 16]]
reference = dict(publicInputs=public+['1800000000', '1800000900'], rootHash=root_hash.hex(),
                 tbsLength=len(card.tbs_certificate_bytes), tbsHash=sha256(card.tbs_certificate_bytes).hexdigest(),
                 rootRedcHash=sha256(((1 << 4102)//root_n).to_bytes(257, 'big')).hexdigest(),
                 cardRedcHash=sha256(((1 << 4102)//card_n).to_bytes(257, 'big')).hexdigest())
(out / 'age-witness-reference.json').write_text(json.dumps(reference, indent=2)+'\n')
