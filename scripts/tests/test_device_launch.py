"""Unit fixtures only: these tests never report a device installation as real."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("device_launch", Path(__file__).resolve().parents[1] / "device-launch.py")
launch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(launch)


def device(udid="00008110-0000000000000001", **updates):
    value = {
        "identifier": "00000000-0000-0000-0000-000000000001",
        "hardwareProperties": {"platform": "iOS", "deviceType": "iPhone", "udid": udid},
        "deviceProperties": {"osVersionNumber": "26.0"},
        "connectionProperties": {"tunnelState": "connected", "pairingState": "paired"},
    }
    value.update(updates)
    return value


def result(*devices):
    return {"info": {"outcome": "success"}, "result": {"devices": list(devices)}}


class DeviceLaunchTests(unittest.TestCase):
    def test_selects_connected_iphone_and_ignores_disconnected_pairings(self):
        offline = device("00008110-0000000000000002", connectionProperties={"tunnelState": "disconnected", "pairingState": "paired"})
        self.assertEqual(launch.choose_device(result(offline, device())), device()["hardwareProperties"]["udid"])

    def test_does_not_guess_between_two_phones(self):
        devices = result(device(), device("00008110-0000000000000002"))
        with self.assertRaises(ValueError):
            launch.choose_device(devices)
        self.assertEqual(launch.choose_device(devices, "00008110-0000000000000002"), "00008110-0000000000000002")

    def test_rejects_unpaired_old_os_non_iphone_and_failed_discovery(self):
        invalid = [
            device(connectionProperties={"tunnelState": "connected", "pairingState": "unpaired"}),
            device(deviceProperties={"osVersionNumber": "18.6"}),
            device(hardwareProperties={"platform": "iOS", "deviceType": "iPad", "udid": "00008110-0000000000000001"}),
        ]
        for entry in invalid:
            with self.subTest(entry=entry), self.assertRaises(ValueError):
                launch.choose_device(result(entry))
        failed = result(device())
        failed["info"]["outcome"] = "failed"
        with self.assertRaises(ValueError):
            launch.choose_device(failed)

    def test_requested_missing_phone_cannot_fall_back_to_another(self):
        with self.assertRaises(ValueError):
            launch.choose_device(result(device()), "00008110-0000000000000002")

    def test_team_requires_an_unambiguous_identity_or_explicit_valid_choice(self):
        self.assertEqual(launch.choose_team({"AAAAAAAAAA"}), "AAAAAAAAAA")
        for teams in [set(), {"AAAAAAAAAA", "BBBBBBBBBB"}]:
            with self.assertRaises(ValueError):
                launch.choose_team(teams)
        self.assertEqual(launch.choose_team({"AAAAAAAAAA", "BBBBBBBBBB"}, "BBBBBBBBBB"), "BBBBBBBBBB")
        with self.assertRaises(ValueError):
            launch.choose_team(set(), "$(unexpected)")
