"""Apply one reviewed memory-boundary fix to the pinned public Groth16 template.

Not an audit or an approval to deploy the experimental upstream backend.
"""
from hashlib import sha256
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_bytes()
assert sha256(source).hexdigest() == "35aad9eaafb5bc492dc167d0e5e0d1a1adedbd37fce5ec9a290dfa3e396f18f2", "Unreviewed upstream template"
text = source.decode()
assert text.count("uint256[4] memory buf") == 3
# _msmStep uses two accumulator words plus three ECMUL input words. The fifth
# word is written before the precompile; four words was out of bounds under IR.
text = text.replace("uint256[4] memory buf", "uint256[5] memory buf")
Path(sys.argv[2]).write_text(text)
