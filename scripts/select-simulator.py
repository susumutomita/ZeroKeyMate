#!/usr/bin/env python3
"""Select an installed, available iOS 26+ iPhone runtime without creating fake devices."""
import json
import os
import re
import subprocess
import sys

try:
    result = subprocess.run(['xcrun', 'simctl', 'list', 'devices', 'available', '--json'],
                            check=True, capture_output=True, text=True, timeout=30)
    devices = json.loads(result.stdout)['devices']
    candidates = []
    for runtime, entries in devices.items():
        match = re.search(r'iOS-(\d+)-(\d+)', runtime)
        if not match or int(match[1]) < 26:
            continue
        for entry in entries:
            if entry.get('isAvailable') and entry.get('name', '').startswith('iPhone'):
                score = (int(match[1]), int(match[2]), entry['name'] == 'iPhone 17 Pro', entry['state'] == 'Booted')
                candidates.append((score, entry))
    requested = os.environ.get('MATE_SIMULATOR_UDID')
    if requested:
        candidates = [candidate for candidate in candidates if candidate[1]['udid'] == requested]
    if not candidates:
        raise ValueError('No matching iOS 26+ iPhone Simulator is installed. Install an iOS runtime in Xcode Settings > Components.')
    print(max(candidates, key=lambda item: item[0])[1]['udid'])
except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
    print(str(error), file=sys.stderr)
    sys.exit(1)
