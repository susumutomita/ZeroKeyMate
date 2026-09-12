import importlib.util
import json
from hashlib import sha256
from pathlib import Path
import unittest

spec=importlib.util.spec_from_file_location('age_artifacts',Path(__file__).resolve().parents[1]/'age_artifacts.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)

def pin(record):
    return sha256(json.dumps(record,sort_keys=True,separators=(',',':')).encode()).hexdigest()

class ReviewedAgeStatementTests(unittest.TestCase):
    def setUp(self):
        self.actual={'circuits/jpki_age/Nargo.toml':'manifest','circuits/jpki_age/src/main.nr':'circuit'}
    def test_original_reviewed_record_remains_usable_without_repinning(self):
        old={**self.actual,'circuits/jpki_age/README.md':'old documentation',
             'circuits/jpki_age/target/mate_jpki_age.json':'old build','circuits/jpki_age/.gitignore':'old ignore'}
        module.validate_statement(self.actual,old,pin(old))
    def test_current_record_is_accepted(self):
        module.validate_statement(self.actual,self.actual,pin(self.actual))
    def test_changed_added_and_missing_circuit_sources_are_rejected(self):
        for current in [{**self.actual,'circuits/jpki_age/src/main.nr':'changed'},
                        {**self.actual,'circuits/jpki_age/src/extra.nr':'added'},
                        {'circuits/jpki_age/Nargo.toml':'manifest'}]:
            with self.assertRaises(AssertionError):module.validate_statement(current,self.actual,pin(self.actual))
    def test_editing_an_ignored_historical_entry_still_breaks_the_reviewed_pin(self):
        old={**self.actual,'circuits/jpki_age/README.md':'old'}
        with self.assertRaises(AssertionError):module.validate_statement(self.actual,{**old,'circuits/jpki_age/README.md':'changed'},pin(old))
    def test_unknown_record_entries_cannot_be_silently_ignored(self):
        record={**self.actual,'unreviewed-file':'extra'}
        with self.assertRaises(AssertionError):module.validate_statement(self.actual,record,pin(record))
