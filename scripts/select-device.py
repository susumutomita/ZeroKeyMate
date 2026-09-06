#!/usr/bin/env python3
"""Select exactly one connected iPhone; never guess between multiple devices."""
import json
from pathlib import Path
import subprocess
import tempfile
import sys
try:
    with tempfile.TemporaryDirectory() as temporary:
        output = Path(temporary) / 'devices.json'
        subprocess.run(['xcrun', 'devicectl', 'list', 'devices', '--json-output', str(output)],
                       check=True, capture_output=True, timeout=30)
        entries = json.loads(output.read_text())['result']['devices']
    candidates = [device for device in entries
                  if device.get('hardwareProperties', {}).get('deviceType') == 'iPhone'
                  and device.get('connectionProperties', {}).get('pairingState') == 'paired']
    if len(candidates) != 1:
        raise ValueError('Pair and connect one unlocked iPhone, or use ./mate --device IDENTIFIER explicitly.')
    print(candidates[0]['identifier'])
except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
    print(str(error), file=sys.stderr)
    sys.exit(1)
