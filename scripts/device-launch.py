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


def choose_device(document, requested="auto"):
    if document.get("info", {}).get("outcome") != "success":
        raise ValueError("iPhoneの端末一覧を取得できませんでした。CoreDeviceServiceとXcodeの接続状態を確認してください。")
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
        if connection.get("tunnelState") != "connected" or connection.get("pairingState") != "paired":
            continue
        if requested != "auto" and requested not in (udid, device.get("identifier")):
            continue
        candidates.append(udid)
    candidates = sorted(set(candidates))
    if not candidates:
        raise ValueError("接続済みのiOS 26以降のiPhoneが見つかりません。USB接続・ロック解除・Macの信頼・Developer Modeを確認してください。")
    if len(candidates) != 1:
        raise ValueError("iPhoneが複数接続されています。MATE_DEVICE_UDID=対象のUDID make start で指定してください。")
    return candidates[0]


def choose_team(teams, requested=""):
    if requested:
        if not re.fullmatch(r"[A-Z0-9]{10}", requested):
            raise ValueError("MATE_DEVELOPMENT_TEAMには10文字のTeam IDを指定してください。")
        return requested
    teams = set(teams)
    if not teams:
        raise ValueError("Apple Developmentの署名用Teamが見つかりません。XcodeでApple Accountと開発用証明書を設定してください。")
    if len(teams) != 1:
        raise ValueError("署名用Teamが複数あります。MATE_DEVELOPMENT_TEAM=対象のTEAM_ID make start で指定してください。")
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
            raise ValueError("CoreDeviceServiceへ接続できず、iPhoneを選択できませんでした。XcodeのDevices and Simulatorsで接続を確認してください。インストールは実行していません。") from error
        print(choose_device(json.loads(output.read_text()), sys.argv[2] if len(sys.argv) > 2 else "auto"))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
