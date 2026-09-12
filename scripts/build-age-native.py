"""Build the independent age FFI from the verified, masked public backend.

Run build-age-evm.py first. --ios builds unsigned device/Simulator libraries, not
an installation. Never reads .env, wallet keys or signing identities.
"""
from age_sources import CONFIG, materialize
from hashlib import sha256
from pathlib import Path
import argparse
import json
import os
import platform
import plistlib
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / ".build/age-proof-engine"
SOURCE = BASE / "provekit"
NATIVE = ROOT / "native/age-proof"
args = argparse.ArgumentParser()
args.add_argument("--ios", action="store_true")
options = args.parse_args()
assert platform.system() == "Darwin" and platform.machine() == "arm64", "Apple Silicon build host required"
record = json.loads((BASE / "artifacts/provenance.json").read_text())
assert record["sameWitnessCommitmentsDiffer"] is True
assert record["hidingPatchSHA256"] == sha256((ROOT / "patches/provekit-groth16-hiding.patch").read_bytes()).hexdigest()
assert record["sourceArchives"]["provekit"] == CONFIG["provekit"]
# A marker/provenance file does not authenticate cached source. Re-extract the
# checked upstream archive and apply both checked patches on every native build.
materialize("provekit", BASE, SOURCE)
for name, field in [("provekit-groth16-noir-directory.patch", "compilerPatchSHA256"),
                    ("provekit-groth16-hiding.patch", "hidingPatchSHA256")]:
    patch = ROOT / "patches" / name
    assert sha256(patch.read_bytes()).hexdigest() == record[field]
    applied = subprocess.run(["patch", "--batch", "-p1", "-i", str(patch)], cwd=SOURCE,
                             capture_output=True, text=True)
    assert applied.returncode == 0, "Public backend patch did not apply cleanly"
patched_source = {str(p.relative_to(SOURCE)): sha256(p.read_bytes()).hexdigest()
                  for p in sorted(SOURCE.rglob("*")) if p.is_file()}

shutil.copytree(NATIVE, SOURCE / "tooling/mate-age-ffi", dirs_exist_ok=True,
                ignore=shutil.ignore_patterns("Runtime", ".build"))
manifest = SOURCE / "Cargo.toml"
entry = '  "tooling/mate-age-ffi",\n'
text = manifest.read_text()
if entry not in text:
    assert text.count("members = [\n") == 1
    manifest.write_text(text.replace("members = [\n", "members = [\n" + entry))
# Adding a local workspace package must not resolve or update other dependencies.
package = '''[[package]]
name = "mate-age-ffi"
version = "0.1.0"
dependencies = [
 "ark-bn254",
 "ark-ec",
 "ark-ff 0.5.0",
 "ark-serialize 0.5.0",
 "noirc_abi",
 "provekit-common",
 "provekit-groth16",
 "provekit-prover",
 "provekit-verifier",
 "rayon",
 "sha3",
]
'''
lock = SOURCE / "Cargo.lock"
text = lock.read_text()
if 'name = "mate-age-ffi"' not in text:
    lock.write_text(text.rstrip() + "\n\n" + package)
else:
    start = text.index('[[package]]\nname = "mate-age-ffi"')
    end = text.find('[[package]]', start + 1)
    if end == -1:
        end = len(text)
    lock.write_text(text[:start] + package + "\n" + text[end:])
toolchain = ROOT / ".tools/rustup/toolchains/nightly-2026-03-04-aarch64-apple-darwin/bin"
cargo = str(toolchain / "cargo") if (toolchain / "cargo").exists() else "cargo"
env = {**os.environ, "CARGO_HOME": str(BASE / "cargo"), "CARGO_TARGET_DIR": str(BASE / "target"),
       "RUSTUP_TOOLCHAIN": "nightly-2026-03-04", "CARGO_BUILD_JOBS": "2", "RAYON_NUM_THREADS": "2",
       "IPHONEOS_DEPLOYMENT_TARGET": "17.0", "GIT_CONFIG_NOSYSTEM": "1",
       "GIT_CONFIG_GLOBAL": os.devnull, "GIT_TERMINAL_PROMPT": "0"}
if (toolchain / "rustc").exists():
    env.update(RUSTC=str(toolchain / "rustc"), RUSTDOC=str(toolchain / "rustdoc"))


def run(name, command):
    print(name, flush=True)
    with (BASE / (name + ".log")).open("w") as log:
        result = subprocess.run(list(map(str, command)), cwd=ROOT, env=env, stdout=log, stderr=log)
    assert result.returncode == 0, f"Failed {name}; inspect its build log"


common = [cargo, "build", "--release", "--locked", "--offline", "-p", "mate-age-ffi", "--manifest-path", manifest]
run("native-host-build", common)
libraries = [BASE / "target/release/libmate_age_ffi.a", BASE / "target/release/libmate_age_ffi.dylib"]
if options.ios:
    frameworks = []
    for target in ["aarch64-apple-ios-sim", "aarch64-apple-ios"]:
        run("native-" + target, common + ["--target", target])
        libraries.append(BASE / "target" / target / "release/libmate_age_ffi.a")
        # A named static framework avoids both Rust libraries copying a bare
        # include/module.modulemap into the same Xcode build directory.
        wrapper = BASE / "native-frameworks" / target / "MateAgeRuntime.framework"
        (wrapper / "Headers").mkdir(parents=True, exist_ok=True)
        (wrapper / "Modules").mkdir(exist_ok=True)
        shutil.copyfile(libraries[-1], wrapper / "MateAgeRuntime")
        shutil.copyfile(NATIVE / "include/mate_age.h", wrapper / "Headers/mate_age.h")
        (wrapper / "Modules/module.modulemap").write_text('framework module MateAgeRuntime { umbrella header "mate_age.h" export * }\n')
        (wrapper / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleExecutable": "MateAgeRuntime", "CFBundleIdentifier": "com.zerokeymate.age-runtime",
            "CFBundlePackageType": "FMWK", "CFBundleShortVersionString": "1.0", "CFBundleVersion": "1",
            "MinimumOSVersion": "17.0", "CFBundleSupportedPlatforms": ["iPhoneSimulator" if target.endswith("-sim") else "iPhoneOS"]}))
        frameworks.append(wrapper)
    framework = BASE / "MateAge.xcframework"
    if framework.exists():
        shutil.rmtree(framework) # Only this script's generated unsigned output.
    run("native-framework", ["xcodebuild", "-create-xcframework",
        "-framework", frameworks[0], "-framework", frameworks[1], "-output", framework])
    runtime = NATIVE / "swift/Runtime"
    runtime.mkdir(exist_ok=True)
    link = runtime / "MateAge.xcframework"
    if link.is_symlink():
        link.unlink()
    assert not link.exists(), "Refusing to replace a non-generated runtime"
    link.symlink_to(framework, target_is_directory=True)
record = {"backend": "experimental masked Groth16", "deviceAcceptance": False,
          "hidingPatchSHA256": record["hidingPatchSHA256"],
          "patchedSourceSHA256": patched_source,
          "ffiSHA256": {str(p.relative_to(ROOT)): sha256(p.read_bytes()).hexdigest()
                        for p in sorted(NATIVE.rglob("*")) if p.is_file() and "Runtime" not in p.parts and ".build" not in p.relative_to(NATIVE).parts},
          "libraries": {str(p.relative_to(ROOT)): sha256(p.read_bytes()).hexdigest() for p in libraries}}
(BASE / "native-provenance.json").write_text(json.dumps(record, indent=2) + "\n")
print("Unsigned native age libraries built; no private input or key accessed.")
