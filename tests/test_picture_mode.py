"""S9 OSD calibration and readback contract; no hardware writes in tests."""
import sys
import unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import samsung_ipc as ipc


class PictureModeTests(unittest.TestCase):
    def test_write_and_read_labels_match_osd_calibration(self):
        for name, code, label in [("srgb", "Gen_327712", "sRGB"), ("dci-p3", "Gen_327714", "DCI-P3"), ("p3", "Gen_327714", "DCI-P3"), ("bt709", "Gen_327713", "BT.709")]:
            with self.subTest(name=name), \
                 patch.object(ipc, "credentials", return_value=("test", "test")), \
                 patch.object(ipc, "rpc", side_effect=[({"pictureMode": code}, {}), ({"pictureMode": code}, {})]) as rpc:
                self.assertEqual(ipc.set_picture_mode(name), code)
                self.assertEqual(rpc.call_args_list[0].args, ("pictureModeControl", {"pictureMode": code}))
                self.assertEqual(rpc.call_args_list[1].args, ("getTVStates",))
                self.assertEqual(ipc.picture_mode_label(code), label)

    def test_write_echo_is_not_confirmation(self):
        with patch.object(ipc, "credentials", return_value=("test", "test")), \
             patch.object(ipc, "rpc", side_effect=[({"pictureMode": "Gen_327714"}, {}), ({"pictureMode": "Gen_327712"}, {})]):
            with self.assertRaises(ipc.IPCError):
                ipc.set_picture_mode("dci-p3")

    def test_unknown_raw_mode_is_preserved(self):
        self.assertEqual(ipc.picture_mode_label("Gen_999999"), "Gen_999999")
