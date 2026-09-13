mod date;
mod der;
mod certificate;
mod hash;
use bignum::{params::BigNumParams, RuntimeBigNum};
use rsa::rsa::verify_sha256_pkcs1v15;
use hash::{digest,sha256_var};

// Experimental only. A gate MUST pin an approved root_key_hash and bind these
// public values to an unexpired order. No such gate is deployed or enabled yet.
fn main(
    order_high: pub u128, order_low: pub u128, nonce_high: pub u128, nonce_low: pub u128, root_high: pub u128, root_low: pub u128,
    reference_time: pub u64, expires_at: pub u64,
    tbs: [u8;2048], tbs_length: u32, certificate_signature: [u8;256],
    root_modulus: [u8;256], root_redc: [u8;257],
    card_signature: [u8;256], card_redc: [u8;257]
) {
    let order_hash = unpack(order_high,order_low);
    let nonce = unpack(nonce_high,nonce_low);
    let root_key_hash = unpack(root_high,root_low);
    assert((reference_time >= 1704067200) & (reference_time <= 4102444800));
    assert((expires_at > reference_time) & (expires_at <= reference_time+900));
    let mut order_nonzero = false; let mut nonce_nonzero = false;
    for i in 0..32 {order_nonzero = order_nonzero | (order_hash[i] != 0); nonce_nonzero = nonce_nonzero | (nonce[i] != 0);}
    assert(order_nonzero & nonce_nonzero);
    assert(tbs_length <= 2048);
    for i in 0..2048 {if i >= tbs_length {assert(tbs[i] == 0);}}
    assert(digest(root_modulus) == root_key_hash, "Wrong root key");
    let (card_key,dob) = certificate::fields(tbs,tbs_length,reference_time,expires_at);
    verify_rsa(sha256_var(tbs,tbs_length),certificate_signature,root_modulus,root_redc);
    let domain: [u8;32] = [90,101,114,111,75,101,121,77,97,116,101,32,97,103,101,32,97,117,116,104,101,110,116,105,99,97,116,105,111,110,32,118];
    // Exact Swift JPKIChallenge bytes: "ZeroKeyMate age authentication v1\0".
    let mut message: [u8;98] = [0;98];
    for i in 0..32 {message[i] = domain[i];}
    message[32] = 49; message[33] = 0;
    for i in 0..32 {message[34+i] = order_hash[i]; message[66+i] = nonce[i];}
    verify_rsa(digest(message),card_signature,card_key,card_redc);
    date::adult(dob,reference_time);
}

fn limbs<let N: u32>(bytes: [u8;N]) -> [u128;18] {
    let mut out: [u128;18] = [0;18];
    for i in 0..N {out[i/15] += (bytes[N-i-1] as u128) << (((i%15)*8) as u128);}
    out
}
fn verify_rsa(hash: [u8;32], signature: [u8;256], modulus: [u8;256], redc: [u8;257]) {
    assert(modulus[0] >= 128); assert((modulus[255] & 1) == 1);
    let params: BigNumParams<18,2048> = BigNumParams::new(false,limbs(modulus),limbs(redc));
    let sig: RuntimeBigNum<18,2048> = RuntimeBigNum::from_be_bytes(params,signature);
    assert(verify_sha256_pkcs1v15(hash,sig,65537), "Invalid RSA signature");
}

fn unpack(high: u128, low: u128) -> [u8;32] {
    let mut bytes: [u8;32] = [0;32];
    let high_bytes: [u8;16] = (high as Field).to_be_bytes();
    let low_bytes: [u8;16] = (low as Field).to_be_bytes();
    for i in 0..16 {
        bytes[i] = high_bytes[i];
        bytes[16+i] = low_bytes[i];
    }
    bytes
}
