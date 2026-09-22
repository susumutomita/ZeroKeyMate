"""Run both real native provers with the fixed public synthetic fixture only.

No card/credential input option. Reports timings and rejects a changed order;
never exports the experimental proof or contacts a network.
"""
from pathlib import Path
from hashlib import file_digest, sha256
import argparse
import ctypes
import importlib.util
import json
import platform
import tempfile
import time
import tomllib

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--whir-directory', type=Path, required=True)
parser.add_argument('--groth16-directory', type=Path, required=True)
args = parser.parse_args()
pins = json.loads((ROOT / 'config/age-benchmark-pins.json').read_text())
age = json.loads((ROOT / 'config/age-runtime-pins.json').read_text())
fixture = ROOT / 'native/age-proof/src/benchmark-input.json'
assert sha256(fixture.read_bytes()).hexdigest() == pins['fixtureSHA256']
assert pins['syntheticOnly'] and pins['statementSHA256'] == age['statementSHA256']
# Reproduce the compiled fixture from the repository's synthetic certificates.
spec = importlib.util.spec_from_file_location('fixtures', ROOT / 'scripts/jpki-age-fixtures.py')
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
with tempfile.TemporaryDirectory(prefix='mate-public-benchmark-') as temporary:
    out = Path(temporary); module.fixtures(out)
    values = tomllib.loads((out / 'valid.toml').read_text())
    assert json.loads(fixture.read_text()) == values

class Metrics(ctypes.Structure):
    _fields_ = [(key, ctypes.c_uint64) for key in ['version', 'worker_threads', 'total_us',
        'prover_load_us', 'input_parse_us', 'witness_and_proof_us', 'verifier_load_us', 'verify_us', 'encode_us']]
class Benchmark(ctypes.Structure):
    _fields_ = [('timing', Metrics), ('serialized_proof_bytes', ctypes.c_uint64),
        ('changed_order_rejected', ctypes.c_uint64), ('changed_order_verify_us', ctypes.c_uint64)]
assert ctypes.sizeof(Benchmark) == 96
base = ROOT / '.build/age-proof-engine'
library = base / 'target/release' / ('libmate_age_ffi.dylib' if platform.system() == 'Darwin' else 'libmate_age_ffi.so')
runtime = ctypes.CDLL(str(library)); run = runtime.mate_age_benchmark
run.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint32, ctypes.POINTER(Benchmark)]
run.restype = ctypes.c_int32
keys = []
for backend, directory, stem, expected in [(0, args.groth16_directory, 'age',
        {'pkp': age['proverSHA256'], 'pkv': age['verifierSHA256']}),
        (1, args.whir_directory, 'age-whir', {'pkp': pins['whir']['pkpSHA256'], 'pkv': pins['whir']['pkvSHA256']})]:
    paths = []
    for ext in ['pkp', 'pkv']:
        path = directory / (stem + '.' + ext)
        with path.open('rb') as file: assert file_digest(file, 'sha256').hexdigest() == expected[ext]
        paths.append(str(path.resolve()).encode())
    keys.append(paths)
reports = []
for sample in range(2):
    for backend in [0, 1]:
        output = Benchmark(); start = time.monotonic()
        code = run(*keys[backend], backend, ctypes.byref(output))
        assert code == 0, ('benchmark failed', backend, code)
        timing = {key: getattr(output.timing, key) for key, _ in Metrics._fields_}
        assert timing['version'] == 1 and timing['worker_threads'] == 2
        assert 0 < sum(value for key,value in timing.items() if key.endswith('_us') and key != 'total_us') <= timing['total_us']
        assert output.changed_order_rejected == 1 and output.serialized_proof_bytes > 0
        report = {'backend': ['Groth16','WHIR'][backend], 'sample': sample, 'timing': timing,
            'wallSeconds': round(time.monotonic() - start, 6), 'proofBytes': output.serialized_proof_bytes,
            'changedOrderRejected': True, 'changedOrderVerifyMicroseconds': output.changed_order_verify_us}
        reports.append(report); print(json.dumps(report), flush=True)
invalid = Benchmark(); ctypes.memset(ctypes.byref(invalid), 255, ctypes.sizeof(invalid))
assert run(None, None, 99, ctypes.byref(invalid)) == 1
assert bytes(invalid) == bytes(ctypes.sizeof(invalid)), 'Failure must clear output'
for backend in [0,1]:
    invalid = Benchmark()
    assert run(*keys[backend], 1-backend, ctypes.byref(invalid)) == 2, 'Mismatched backend accepted'
    assert bytes(invalid) == bytes(ctypes.sizeof(invalid))
evidence = {'syntheticOnly': True, 'physicalDevice': False, 'os': platform.platform(),
    'architecture': platform.machine(), 'pins': pins, 'samples': reports,
    'nativeLibrarySHA256': sha256(library.read_bytes()).hexdigest(),
    'cacheNote': 'Repeated calls in one process; file caches uncontrolled. Native proof format, not EVM calldata.'}
(base / 'synthetic-benchmark.json').write_text(json.dumps(evidence, indent=2) + '\n')
