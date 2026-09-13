#!/usr/bin/env python3
"""Select a real connected iPhone and the team of a usable signing identity."""
import hashlib
import json
import os
from pathlib import Path
import re
import ssl
import subprocess
import sys
import tempfile


def choose_device(document, requested="auto", *, allow_disconnected=False):
    if document.get("info", {}).get("outcome") != "success":
        raise ValueError("Could not list iPhones. Check CoreDeviceService and the connection in Xcode.")
    candidates = []
    for device in document.get("result", {}).get("devices", []):
        hardware = device.get("hardwareProperties", {})
        properties = device.get("deviceProperties", {})
        connection = device.get("connectionProperties", {})
        if hardware.get("platform") != "iOS" or not (
            hardware.get("deviceType") == "iPhone" or str(hardware.get("productType", "")).startswith("iPhone")
        ):
            continue
        version = re.match(r"^(\d+)(?:\.|$)", str(properties.get("osVersionNumber", "")))
        udid = hardware.get("udid", "")
        if not version or int(version[1]) < 26 or not re.fullmatch(r"[0-9A-Fa-f-]{20,40}", udid):
            continue
        if connection.get("pairingState") != "paired" or (not allow_disconnected and connection.get("tunnelState") != "connected"):
            continue
        if requested != "auto" and requested not in (udid, device.get("identifier")):
            continue
        candidates.append(udid)
    candidates = sorted(set(candidates))
    if not candidates:
        raise ValueError("No connected iPhone running iOS 26 or later was found. Check USB, unlock the phone, trust this Mac and enable Developer Mode.")
    if len(candidates) != 1:
        raise ValueError("Multiple iPhones are connected. Select one with MATE_DEVICE_UDID=UDID make start-device.")
    return candidates[0]


def choose_team(teams, requested=""):
    if requested:
        if not re.fullmatch(r"[A-Z0-9]{10}", requested):
            raise ValueError("MATE_DEVELOPMENT_TEAM must contain a 10-character Team ID.")
        return requested
    teams = set(teams)
    if not teams:
        raise ValueError("No Apple Development signing team was found. Set up your Apple Account and development certificate in Xcode.")
    if len(teams) != 1:
        raise ValueError("Multiple signing teams were found. Select one with MATE_DEVELOPMENT_TEAM=TEAM_ID make start-device.")
    return next(iter(teams))


def run(arguments, **kwargs):
    return subprocess.run(arguments, check=True, capture_output=True, text=True, timeout=30, **kwargs).stdout


def signing_teams():
    identities = run(["security", "find-identity", "-v", "-p", "codesigning"])
    valid = re.findall(r'^\s*\d+\)\s+([A-Fa-f0-9]{40})\s+"((?:Apple Development|iPhone Developer):[^"\n]+)"', identities, re.M)
    teams = set()
    for fingerprint, name in valid:
        pem = run(["security", "find-certificate", "-a", "-c", name, "-p"])
        for certificate in re.findall(r"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----", pem, re.S):
            der = ssl.PEM_cert_to_DER_cert(certificate)
            if hashlib.sha1(der).hexdigest().lower() != fingerprint.lower():
                continue
            # The parenthesized ID in the certificate CN can be the person's ID.
            # Apple's signing Team ID is the subject OU of this exact identity.
            subject = run(["openssl", "x509", "-noout", "-subject", "-nameopt", "RFC2253"], input=certificate)
            match = re.search(r"(?:^|,)OU=([A-Z0-9]{10})(?:,|$)", subject.removeprefix("subject=").strip())
            if match:
                teams.add(match[1])
    return teams


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ("device", "team"):
        raise ValueError("Usage: device-launch.py device [UDID|auto] | team")
    if sys.argv[1] == "team":
        requested = os.environ.get("MATE_DEVELOPMENT_TEAM", "")
        print(choose_team(set() if requested else signing_teams(), requested))
        return
    root = Path(__file__).resolve().parents[1]
    (root / ".build").mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="device-discovery-", dir=root / ".build") as directory:
        output = Path(directory) / "devices.json"
        try:
            run(["xcrun", "devicectl", "--timeout", "20", "list", "devices", "--json-output", str(output)])
        except subprocess.SubprocessError as error:
            raise ValueError("Could not connect to CoreDeviceService to select an iPhone. Check the connection in Xcode Devices and Simulators. Nothing was installed.") from error
        requested = sys.argv[2] if len(sys.argv) > 2 else "auto"
        document = json.loads(output.read_text())
        try:
            selected = choose_device(document, requested)
        except ValueError:
            # CoreDevice lists Wi-Fi pairings before opening their on-demand tunnel.
            # Select only one eligible pairing, then prove a live connection before
            # handing its UDID to the build/install path. Never unpair or trust devices.
            candidate = choose_device(document, requested, allow_disconnected=True)
            try:
                run(["xcrun", "devicectl", "--timeout", "20", "device", "info", "details", "--device", candidate])
                run(["xcrun", "devicectl", "--timeout", "20", "list", "devices", "--json-output", str(output)])
                selected = choose_device(json.loads(output.read_text()), candidate)
            except (subprocess.SubprocessError, ValueError) as error:
                raise ValueError("The paired iPhone could not be connected. Unlock it and connect USB or the same Wi-Fi network, then retry. Nothing was installed.") from error
        print(selected)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
