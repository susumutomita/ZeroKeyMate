use anyhow::{bail, ensure, Context, Result};
use ark_ff::{BigInteger, PrimeField};
use provekit_common::{file::read, FieldElement, NoirProof, Verifier};
use provekit_verifier::Verify;
use serde::Serialize;
use std::{env, fs, path::PathBuf};

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Statement {
    policy_hash: String,
    action_hash: String,
    spent: String,
    amount: String,
    service: u8,
}

fn bounded_u64(value: &FieldElement) -> Result<u64> {
    let bytes = value.into_bigint().to_bytes_be();
    ensure!(bytes.len() >= 8, "unexpected field width");
    ensure!(bytes[..bytes.len()-8].iter().all(|&v| v == 0), "public integer exceeds u64");
    Ok(u64::from_be_bytes(bytes[bytes.len()-8..].try_into()?))
}

fn byte_hash(values: &[FieldElement]) -> Result<String> {
    ensure!(values.len() == 32, "expected 32 public bytes");
    let mut result = String::from("0x");
    for value in values {
        let byte = u8::try_from(bounded_u64(value)?).context("public hash byte out of range")?;
        result.push_str(&format!("{byte:02x}"));
    }
    Ok(result)
}

#[cfg(target_os = "linux")]
fn constrain_process() -> Result<()> {
    // A compressed proof is adversarial input. Resource limits apply before decode.
    let memory = libc::rlimit { rlim_cur: 2 * 1024 * 1024 * 1024, rlim_max: 2 * 1024 * 1024 * 1024 };
    let cpu = libc::rlimit { rlim_cur: 60, rlim_max: 60 };
    // SAFETY: pointers refer to initialized rlimit values for this process only.
    ensure!(unsafe { libc::setrlimit(libc::RLIMIT_AS, &memory) } == 0, "cannot limit verifier memory");
    ensure!(unsafe { libc::setrlimit(libc::RLIMIT_CPU, &cpu) } == 0, "cannot limit verifier CPU");
    Ok(())
}
fn run() -> Result<()> {
    #[cfg(target_os = "linux")]
    constrain_process()?;
    let args: Vec<_> = env::args_os().skip(1).collect();
    if args.len() != 2 { bail!("usage: mate-verify VERIFIER.pkv PROOF.np"); }
    let verifier_path = PathBuf::from(&args[0]);
    let proof_path = PathBuf::from(&args[1]);
    let size = fs::metadata(&proof_path)?.len();
    ensure!(size > 0 && size <= 8 * 1024 * 1024, "invalid proof size");
    // Paths are selected by the server, not supplied by the public HTTP request.
    let mut verifier: Verifier = read(&verifier_path).context("load pinned verifier")?;
    let proof: NoirProof = read(&proof_path).context("decode proof")?;
    verifier.verify(&proof).context("cryptographic verification failed")?;
    let inputs = &proof.public_inputs.0;
    ensure!(inputs.len() == 67, "wrong circuit public input count");
    let service = u8::try_from(bounded_u64(&inputs[66])?)?;
    ensure!(service < 2, "unsupported service");
    let statement = Statement {
        policy_hash: byte_hash(&inputs[..32])?,
        action_hash: byte_hash(&inputs[32..64])?,
        spent: bounded_u64(&inputs[64])?.to_string(),
        amount: bounded_u64(&inputs[65])?.to_string(),
        service,
    };
    println!("{}", serde_json::to_string(&statement)?);
    Ok(())
}

fn main() {
    if let Err(error) = run() {
        eprintln!("{error:#}");
        std::process::exit(1);
    }
}
