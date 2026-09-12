import hashlib
import importlib.util
import io
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('age_sources', Path(__file__).parents[1] / 'age_sources.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class AgeSourceTests(unittest.TestCase):
    def archive(self, name='upstream/prover.rs', content=b'checked source'):
        data = io.BytesIO()
        with tarfile.open(fileobj=data, mode='w:gz') as tar:
            item = tarfile.TarInfo(name); item.size = len(content)
            tar.addfile(item, io.BytesIO(content))
        return data.getvalue()

    def test_reextract_discards_changed_code_and_extra_build_scripts(self):
        with tempfile.TemporaryDirectory() as folder:
            destination = Path(folder) / 'source'
            data = self.archive()
            module.extract_clean(data, destination)
            (destination / 'prover.rs').write_text('unmasked modified code')
            (destination / 'build.rs').write_text('unapproved extra build code')
            module.extract_clean(data, destination)
            self.assertEqual((destination / 'prover.rs').read_bytes(), b'checked source')
            self.assertFalse((destination / 'build.rs').exists())

    def test_changed_archive_is_rejected_before_extraction(self):
        with tempfile.TemporaryDirectory() as folder:
            cache = Path(folder)
            good = self.archive()
            (cache / 'synthetic.tar.gz').write_bytes(good + b'changed')
            with patch.dict(module.CONFIG, synthetic={'sha256': hashlib.sha256(good).hexdigest(), 'url': 'https://unused.invalid'}):
                with self.assertRaisesRegex(AssertionError, 'Unexpected public archive'):
                    module.archive_bytes('synthetic', cache)

    def test_archive_cannot_escape_or_replace_symlink_destination(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            with self.assertRaises(tarfile.FilterError):
                module.extract_clean(self.archive('upstream/../../outside.rs'), root / 'source')
            self.assertFalse((root / 'outside.rs').exists())
            (root / 'source').symlink_to(root / 'elsewhere', target_is_directory=True)
            with self.assertRaises(AssertionError):
                module.extract_clean(self.archive(), root / 'source')
