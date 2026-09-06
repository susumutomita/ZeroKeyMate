#!/usr/bin/env python3
"""Compatibility entry point; reports configuration, never claims a verified release."""
import os
from pathlib import Path
root = Path(__file__).resolve().parents[1]
os.chdir(root)
os.execvp("node", ["node", "--env-file-if-exists=.env", "scripts/doctor.mjs"])
