"""Packaging regression fixtures; these are not native proving acceptance."""
import importlib.util
from hashlib import sha256
import json
from pathlib import Path
import plistlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('shop_app', Path(__file__).resolve().parents[1] / 'validate-shop-app.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ShopBundleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.app = Path(self.temp.name)
        (self.app / 'ShopConnection.json').write_text('{}')
        (self.app / 'Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': 'com.zerokeymate.companion', 'CFBundleExecutable': 'ZeroKeyMate'}))
        (self.app / 'Configuration.json').write_text(json.dumps({
            'chainID': 5042002, 'privyAppID': 'public-test-app', 'privyClientID': 'public-test-client'}))
        self.pins = ''
        for name, constant in [('age.pkp', 'proverSHA256'), ('age.pkv', 'verifierSHA256')]:
            value = ('synthetic-' + name).encode()
            (self.app / name).write_bytes(value)
            self.pins += 'static let ' + constant + ' = "' + sha256(value).hexdigest() + '"\n'
        (self.app / 'ZeroKeyMate.debug.dylib').write_bytes(b'synthetic only')
        self.symbols = lambda _: {'_mate_age_prove_measured', '_mate_age_keccak256'}

    def test_complete_fixture_and_companion_only_are_distinguished(self):
        self.assertTrue(module.validate(self.app, self.pins, self.symbols))
        (self.app / 'ShopConnection.json').unlink()
        self.assertFalse(module.validate(self.app, self.pins, lambda _: set()))

    def test_missing_setup_is_rejected_before_installation(self):
        (self.app / 'age.pkp').unlink()
        with self.assertRaisesRegex(ValueError, 'missing its public age-proof setup'):
            module.validate(self.app, self.pins, self.symbols)

    def test_wrong_setup_and_source_only_runtime_are_rejected(self):
        with self.assertRaisesRegex(ValueError, 'missing the current native'):
            module.validate(self.app, self.pins, lambda _: set())
        (self.app / 'age.pkv').write_bytes(b'wrong setup')
        with self.assertRaisesRegex(ValueError, 'does not match'):
            module.validate(self.app, self.pins, self.symbols)

    def test_wrong_network_and_missing_public_wallet_configuration_are_rejected(self):
        for config in [{'chainID': 11155111, 'privyAppID': 'app', 'privyClientID': 'client'}, {'chainID': 5042002}]:
            (self.app / 'Configuration.json').write_text(json.dumps(config))
            with self.assertRaisesRegex(ValueError, 'Arc Testnet'):
                module.validate(self.app, self.pins, self.symbols)
