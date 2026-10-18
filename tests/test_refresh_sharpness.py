"""Sharpness nudge/restore regression tests; never write to real hardware."""
import sys
import unittest
from pathlib import Path
from unittest.mock import patch, call
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import samsung_ipc as ipc


class RefreshSharpnessTests(unittest.TestCase):
    def test_restore_requested_target_including_boundaries(self):
        for target, temporary in [(10, 9), (0, 1), (20, 19)]:
            with self.subTest(target=target), \
                 patch.object(ipc, "set_sharpness") as write, \
                 patch.object(ipc, "get_sharpness", return_value=target), \
                 patch.object(ipc.time, "sleep"):
                self.assertEqual(ipc.refresh_sharpness(target), target)
                self.assertEqual(write.call_args_list, [call(temporary), call(target)])

    def test_first_write_timeout_still_attempts_restore(self):
        with patch.object(ipc, "set_sharpness", side_effect=[ipc.IPCError("timeout"), 10]) as write:
            with self.assertRaisesRegex(ipc.IPCError, "timeout"):
                ipc.refresh_sharpness(10)
            self.assertEqual(write.call_args_list, [call(9), call(10)])

    def test_restore_failure_names_target(self):
        with patch.object(ipc, "set_sharpness", side_effect=[9, ipc.IPCError("offline")]), \
             patch.object(ipc.time, "sleep"):
            with self.assertRaisesRegex(ipc.IPCError, "Không khôi phục.*10"):
                ipc.refresh_sharpness(10)

    def test_readback_mismatch_is_not_success(self):
        with patch.object(ipc, "set_sharpness"), \
             patch.object(ipc, "get_sharpness", return_value=9), \
             patch.object(ipc.time, "sleep"):
            with self.assertRaisesRegex(ipc.IPCError, "Chưa xác nhận"):
                ipc.refresh_sharpness(10)

    def test_invalid_target_never_writes(self):
        with patch.object(ipc, "set_sharpness") as write:
            for target in [-1, 21]:
                with self.assertRaises(ipc.IPCError):
                    ipc.refresh_sharpness(target)
            write.assert_not_called()
