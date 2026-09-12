"""Public synthetic fixtures only. Never accepts a real certificate or private key."""
from copy import deepcopy
from hashlib import sha256
from pathlib import Path
import sys
from cryptography import x509

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "Tests/MateCoreTests/Fixtures/JPKI"


def write_toml(path, values):
    def encode(value):
        # TOML integers are signed 64-bit; Noir accepts decimal strings for u128.
        return '"' + str(value) + '"' if isinstance(value, int) and value > 2**63-1 else str(value)
    path.write_text("".join(f"{key} = {encode(value)}\n" for key, value in values.items()))


def fixtures(out):
    out.mkdir(parents=True, exist_ok=True)
    root = x509.load_der_x509_certificate((FIXTURES / "root.der").read_bytes())
    root_n = root.public_key().public_numbers().n
    root_bytes = root_n.to_bytes(256, "big")
    root_hash = sha256(root_bytes).digest()

    def values(name):
        cert = x509.load_der_x509_certificate((FIXTURES / (name + ".der")).read_bytes())
        data = cert.tbs_certificate_bytes
        assert len(data) <= 2048
        n = cert.public_key().public_numbers().n
        result = {}
        for name, raw in [("order", bytes([1])*32), ("nonce", bytes([2])*32), ("root", root_hash)]:
            result[name+"_high"] = int.from_bytes(raw[:16], "big")
            result[name+"_low"] = int.from_bytes(raw[16:], "big")
        return dict(result, reference_time=1800000000, expires_at=1800000900,
                    tbs=list(data)+[0]*(2048-len(data)), tbs_length=len(data),
                    certificate_signature=list(cert.signature), root_modulus=list(root_bytes),
                    root_redc=list(((1 << 4102)//root_n).to_bytes(257, "big")),
                    card_redc=list(((1 << 4102)//n).to_bytes(257, "big")),
                    card_signature=list((FIXTURES / "card-signature.bin").read_bytes()))

    valid = values("card")
    cases = {"valid": valid}
    for name in ["underage", "unknown-date", "duplicate-date"]:
        cases[name] = values(name)
    for name, mutate in [
        ("changed-order", lambda d: d.update(order_high=d["order_high"] ^ 1)),
        ("changed-nonce", lambda d: d.update(nonce_low=d["nonce_low"] ^ 1)),
        ("wrong-root", lambda d: d.update(root_high=d["root_high"] ^ 1)),
        ("zero-order", lambda d: d.update(order_high=0, order_low=0)),
        ("zero-nonce", lambda d: d.update(nonce_high=0, nonce_low=0)),
        ("bad-card-signature", lambda d: d["card_signature"].__setitem__(0, d["card_signature"][0] ^ 1)),
        ("bad-certificate-signature", lambda d: d["certificate_signature"].__setitem__(0, d["certificate_signature"][0] ^ 1)),
        ("expired-certificate", lambda d: d.update(reference_time=1900000000, expires_at=1900000900)),
        ("not-yet-valid", lambda d: d.update(reference_time=1705000000, expires_at=1705000900)),
        ("long-order", lambda d: d.update(expires_at=d["reference_time"]+901)),
        ("zero-duration", lambda d: d.update(expires_at=d["reference_time"])),
        ("truncated-tbs", lambda d: d.update(tbs_length=d["tbs_length"]-1)),
        ("nonzero-padding", lambda d: d["tbs"].__setitem__(2047, 1)),
        ("tampered-date", lambda d: d["tbs"].__setitem__(bytes(d["tbs"]).index(b"19900102")+7, ord("3"))),
    ]:
        data = deepcopy(valid)
        mutate(data)
        cases[name] = data
    for name, data in cases.items():
        write_toml(out / (name + ".toml"), data)
    return list(cases)


if __name__ == "__main__":
    cases = fixtures(Path(sys.argv[1]))
    print(f"Prepared {len(cases)} synthetic cases. No card or private key accessed.")
