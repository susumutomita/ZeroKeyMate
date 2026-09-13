// SPDX-License-Identifier: Apache-2.0
//! Separate native ABI for the masked age backend. No Verity/pk_* symbols,
//! input persistence, logging, network, wallet or shared prover cache.
use std::{ffi::{c_char, CStr}, path::Path, slice, panic::{catch_unwind, AssertUnwindSafe}};
use ark_bn254::{Fq, G1Affine, G2Affine};
use ark_ec::AffineRepr;
use ark_ff::{BigInteger, PrimeField};
use ark_serialize::CanonicalDeserialize;
use noirc_abi::input_parser::Format;
use provekit_common::{file, NoirProof, Verifier};
use provekit_prover::{read_pkp, Prove, Prover};
use provekit_verifier::Verify;
use std::sync::{Once, atomic::{AtomicBool, Ordering}};

static ACTIVE: AtomicBool = AtomicBool::new(false);
static PANIC_HOOK: Once = Once::new();
struct PrivateCall;
impl Drop for PrivateCall { fn drop(&mut self) { ACTIVE.store(false, Ordering::SeqCst); } }

/// # Safety
/// Input/output buffers must be valid and disjoint. A null input is allowed
/// only for length zero. No path, key, network, allocation or logging occurs.
#[no_mangle]
pub unsafe extern "C" fn mate_age_keccak256(input: *const u8, input_len: usize, out: *mut u8, out_len: usize) -> i32 {
    if out.is_null() || out_len != 32 { return 1; }
    let output = slice::from_raw_parts_mut(out, 32); output.fill(0);
    if input_len > 65536 || (input.is_null() && input_len > 0) { return 1; }
    let bytes = if input_len == 0 { &[] } else { slice::from_raw_parts(input, input_len) };
    use sha3::{Digest, Keccak256};
    output.copy_from_slice(&Keccak256::digest(bytes)); 0
}

/// # Safety
/// Paths must be readable NUL-terminated UTF-8 strings. Input and output must
/// reference disjoint valid buffers of the declared lengths for the whole call.
/// The caller pins setup hashes before calling and must not mutate them during
/// proving. Invoke serially from a background worker, never the UI thread.
#[no_mangle]
pub unsafe extern "C" fn mate_age_prove(
    prover_path: *const c_char, verifier_path: *const c_char,
    input: *const u8, input_len: usize, out: *mut u8, out_len: usize,
) -> i32 {
    if out.is_null() || out_len != 640 { return 1; }
    let output = slice::from_raw_parts_mut(out, out_len);
    output.fill(0);
    if prover_path.is_null() || verifier_path.is_null() || input.is_null()
        || !(2..=40000).contains(&input_len) { return 1; }
    // catch_unwind alone still prints the default panic text, which may contain
    // circuit/input details. Suppress panic payloads during this private call,
    // including Rayon workers; preserve the prior hook outside proving.
    PANIC_HOOK.call_once(|| {
        let previous = std::panic::take_hook();
        std::panic::set_hook(Box::new(move |info| {
            if !ACTIVE.load(Ordering::SeqCst) { previous(info); }
        }));
    });
    if ACTIVE.compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst).is_err() { return 8; }
    let _private_call = PrivateCall;
    let result = catch_unwind(AssertUnwindSafe(|| -> Result<Vec<u8>, i32> {
        let pkp = CStr::from_ptr(prover_path).to_str().map_err(|_| 1)?;
        let pkv = CStr::from_ptr(verifier_path).to_str().map_err(|_| 1)?;
        if pkp.len() > 4096 || pkv.len() > 4096 { return Err(1); }
        let json = std::str::from_utf8(slice::from_raw_parts(input, input_len)).map_err(|_| 1)?;
        // Keep mobile proving bounded without changing the host's global pool.
        // Thread exhaustion is an explicit failure, never a fallback to all cores.
        let pool = rayon::ThreadPoolBuilder::new().num_threads(2).build().map_err(|_| 4)?;
        pool.install(|| {
        let prover = read_pkp(Path::new(pkp)).map_err(|_| 2)?;
        match &prover {
            Prover::Groth16(p) if p.commitment_info.len() == 1
                && p.commitment_info[0].private_committed.last() == Some(&p.blinding_wire) => {},
            _ => return Err(2),
        }
        let inputs = Format::from_ext("json").ok_or(3)?.parse(json, prover.abi()).map_err(|_| 3)?;
        let proof = prover.prove(inputs).map_err(|_| 4)?;
        let mut verifier: Verifier = file::read(Path::new(pkv)).map_err(|_| 2)?;
        verifier.verify(&proof).map_err(|_| 5)?;
        encode(proof)
        })
    }));
    match result {
        Ok(Ok(bytes)) if bytes.len() == 640 => { output.copy_from_slice(&bytes); 0 },
        Ok(Ok(_)) => 6,
        Ok(Err(code)) => code,
        Err(_) => 7,
    }
}

// EVM serialization follows the MIT-licensed public ProveKit PR #447 exporter
// pinned in config/age-proof-sources.json. Conversion stays entirely in memory.
fn encode(proof: NoirProof) -> Result<Vec<u8>, i32> {
    let NoirProof::Groth16 { public_inputs, groth16_proof } = proof else { return Err(6); };
    if public_inputs.0.len() != 8 { return Err(6); }
    let g = provekit_groth16::Proof::deserialize_compressed(groth16_proof.as_slice()).map_err(|_| 6)?;
    if g.commitments.len() != 1 { return Err(6); }
    let mut out = Vec::with_capacity(640);
    g1(&mut out, &g.ar)?; g2(&mut out, &g.bs)?; g1(&mut out, &g.krs)?;
    g1(&mut out, &g.commitments[0])?; g1(&mut out, &g.commitment_pok)?;
    for value in public_inputs.0 { fixed(&mut out, &value.into_bigint().to_bytes_be())?; }
    Ok(out)
}
fn fixed(out: &mut Vec<u8>, bytes: &[u8]) -> Result<(), i32> {
    if bytes.len() > 32 { return Err(6); }
    out.resize(out.len() + 32 - bytes.len(), 0); out.extend_from_slice(bytes); Ok(())
}
fn fq(out: &mut Vec<u8>, value: &Fq) -> Result<(), i32> { fixed(out, &value.into_bigint().to_bytes_be()) }
fn g1(out: &mut Vec<u8>, point: &G1Affine) -> Result<(), i32> {
    let (x, y) = point.xy().ok_or(6)?; fq(out, &x)?; fq(out, &y)
}
fn g2(out: &mut Vec<u8>, point: &G2Affine) -> Result<(), i32> {
    let (x, y) = point.xy().ok_or(6)?;
    fq(out, &x.c1)?; fq(out, &x.c0)?; fq(out, &y.c1)?; fq(out, &y.c0)
}
