import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('export_verifier', Path(__file__).parents[1] / 'verify-exported-proof.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ExportVerificationTests(unittest.TestCase):
    """Control-flow tests use a synthetic adapter, not cryptographic evidence."""
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.proof = self.root / 'phone.np'
        self.proof.write_bytes(b'example proof')
        self.key = self.root / 'mate_policy.pkv'
        self.key.write_bytes(b'example key')
        manifest = {'system': 'ProveKit', 'version': '1.0.1', 'circuit': 'mate_policy',
                    'hash': 'skyscraper', 'files': {'mate_policy.pkv': module.digest(self.key.read_bytes())}}
        (self.root / 'manifest.json').write_text(json.dumps(manifest))
        self.binary = self.root / 'verifier'
        self.binary.write_bytes(b'synthetic adapter identity')
        self.report = self.root / 'report.json'

    def run_verification(self, outcomes):
        with patch.object(module.subprocess, 'run', side_effect=outcomes) as runner:
            result = module.verify_export(self.proof, self.root, self.binary, self.report)
        return result, runner

    @staticmethod
    def accepted():
        return subprocess.CompletedProcess([], 0, b'public statement must not be logged', b'')

    @staticmethod
    def rejected():
        return subprocess.CompletedProcess([], 1, b'', b'cryptographic verification failed: invalid')

    def test_success_preserves_inputs_and_withholds_unobserved_device_claims(self):
        original = self.proof.read_bytes()
        result, runner = self.run_verification([self.accepted(), self.rejected(), self.accepted()])
        self.assertEqual(runner.call_count, 3)
        self.assertEqual(self.proof.read_bytes(), original)
        self.assertEqual(result['proofSHA256'], hashlib.sha256(original).hexdigest())
        self.assertEqual(result['deviceOrigin'], 'not-verified')
        self.assertEqual(result['offlineGeneration'], 'not-verified')
        self.assertEqual(os.stat(self.report).st_mode & 0o777, 0o600)
        self.assertNotIn('public statement', self.report.read_text())

    def test_wrong_key_is_rejected_before_executing(self):
        self.key.write_bytes(b'wrong setup')
        with patch.object(module.subprocess, 'run') as runner:
            with self.assertRaises(ValueError):
                module.verify_export(self.proof, self.root, self.binary, self.report)
            runner.assert_not_called()
        self.assertFalse(self.report.exists())

    def test_invalid_original_never_writes_success(self):
        with self.assertRaises(ValueError):
            self.run_verification([self.rejected()])
        self.assertFalse(self.report.exists())

    def test_crash_timeout_and_unrelated_error_are_not_tamper_rejection(self):
        for failure in [subprocess.CompletedProcess([], -11, b'', b''),
                        subprocess.CompletedProcess([], 1, b'', b'load pinned verifier'),
                        subprocess.TimeoutExpired('verifier', 120), self.accepted()]:
            with self.subTest(failure=failure):
                with self.assertRaises((ValueError, subprocess.TimeoutExpired)):
                    self.run_verification([self.accepted(), failure])
                self.assertFalse(self.report.exists())

    def test_recheck_failure_never_writes_success(self):
        with self.assertRaises(ValueError):
            self.run_verification([self.accepted(), self.rejected(), self.rejected()])
        self.assertFalse(self.report.exists())

    def test_existing_report_is_never_overwritten(self):
        self.report.write_text('earlier evidence')
        with self.assertRaises(FileExistsError):
            self.run_verification([self.accepted(), self.rejected(), self.accepted()])
        self.assertEqual(self.report.read_text(), 'earlier evidence')

    def test_decode_rejection_is_labeled_separately(self):
        result, _ = self.run_verification([self.accepted(), subprocess.CompletedProcess(
            [], 1, b'', b'decode proof: invalid format'), self.accepted()])
        self.assertEqual(result['modifiedRejection'], 'decode')


if __name__ == '__main__':
    unittest.main()
