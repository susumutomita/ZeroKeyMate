"""Synthetic-only local acceptance helper. Fresh RSA keys never leave memory."""
import ctypes
from datetime import datetime, timezone
from hashlib import sha256
import json
from pathlib import Path
import sys
from cryptography import x509
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import rsa, padding
from cryptography.x509.oid import NameOID, ObjectIdentifier

base=Path(__file__).resolve().parents[1]/'.build/age-proof-engine'
root_key=rsa.generate_private_key(public_exponent=65537,key_size=2048)
card_key=rsa.generate_private_key(public_exponent=65537,key_size=2048)
root_n=root_key.public_key().public_numbers().n
card_n=card_key.public_key().public_numbers().n
root_bytes=root_n.to_bytes(256,'big')
root_hash=sha256(root_bytes).digest()
print(json.dumps({'syntheticOnly':True,'rootKeyHash':'0x'+root_hash.hex()}),flush=True)
order=json.loads(sys.stdin.readline())
assert set(order)=={'orderHash','paymentNonce','createdAt','expiresAt'}
assert order['expiresAt']==order['createdAt']+900
assert 1735689600<order['createdAt']<1893455100
order_hash=bytes.fromhex(order['orderHash'][2:]);nonce=bytes.fromhex(order['paymentNonce'][2:])
assert len(order_hash)==32 and len(nonce)==32
root_name=x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,'Synthetic checkout root - not J-LIS')])
cert=(x509.CertificateBuilder().subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,'Synthetic card - no real person')]))
 .issuer_name(root_name).public_key(card_key.public_key()).serial_number(2)
 .not_valid_before(datetime(2025,1,1,tzinfo=timezone.utc)).not_valid_after(datetime(2030,1,1,tzinfo=timezone.utc))
 .add_extension(x509.KeyUsage(True,True,False,False,False,False,False,False,False),critical=True)
 .add_extension(x509.SubjectAlternativeName([x509.OtherName(ObjectIdentifier('1.2.392.200149.8.5.5.4'),b'\x0c\x09419900102')]),False)
 .sign(root_key,hashes.SHA256()))
tbs=cert.tbs_certificate_bytes
assert len(tbs)<=2048
challenge=b'ZeroKeyMate age authentication v1\0'+order_hash+nonce
values={}
for name,raw in [('order',order_hash),('nonce',nonce),('root',root_hash)]:
 values[name+'_high']=int.from_bytes(raw[:16],'big');values[name+'_low']=int.from_bytes(raw[16:],'big')
values.update(reference_time=order['createdAt'],expires_at=order['expiresAt'],
 tbs=list(tbs)+[0]*(2048-len(tbs)),tbs_length=len(tbs),certificate_signature=list(cert.signature),
 root_modulus=list(root_bytes),root_redc=list(((1<<4102)//root_n).to_bytes(257,'big')),
 card_redc=list(((1<<4102)//card_n).to_bytes(257,'big')),
 card_signature=list(card_key.sign(challenge,padding.PKCS1v15(),hashes.SHA256())))
runtime=ctypes.CDLL(str(base/'target/release'/('libmate_age_ffi.dylib' if sys.platform=='darwin' else 'libmate_age_ffi.so')))
prove=runtime.mate_age_prove
prove.argtypes=[ctypes.c_char_p,ctypes.c_char_p,ctypes.c_void_p,ctypes.c_size_t,ctypes.c_void_p,ctypes.c_size_t]
prove.restype=ctypes.c_int32
payload=json.dumps({k:str(v) if isinstance(v,int) and v>2**63-1 else v for k,v in values.items()}).encode();buffer=ctypes.create_string_buffer(payload);output=ctypes.create_string_buffer(640)
status=prove(str(base/'artifacts/age.pkp').encode(),str(base/'artifacts/age.pkv').encode(),buffer,len(payload),output,640)
ctypes.memset(buffer,0,len(payload))
assert status==0,('Synthetic local proof failed',status)
print(json.dumps({'syntheticOnly':True,'proof':'0x'+output.raw[:384].hex(),'rootKeyHash':'0x'+root_hash.hex()}),flush=True)
