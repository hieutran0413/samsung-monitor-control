"""Power CLI regression: exercise parsing and RPC mapping without monitor access."""
import contextlib
import io
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import samsung_ipc


class PowerContractTests(unittest.TestCase):
    def test_app_off_argument_reaches_power_rpc(self):
        calls = []
        def rpc(method, params, **kwargs):
            calls.append((method, params))
            return {"power": "powerOff"}, {}
        with patch.object(sys, "argv", ["samsung_ipc.py", "power", "off"]), \
             patch.object(samsung_ipc, "credentials", return_value=("test", "test")), \
             patch.object(samsung_ipc, "rpc", side_effect=rpc), \
             contextlib.redirect_stdout(io.StringIO()) as output:
            samsung_ipc.main()
        self.assertEqual(calls, [("powerControl", {"power": "powerOff"})])
        self.assertEqual(output.getvalue().strip(), "powerOff")

    def test_rpc_failure_does_not_report_success(self):
        with patch.object(samsung_ipc, "credentials", return_value=("test", "test")), \
             patch.object(samsung_ipc, "rpc", side_effect=samsung_ipc.IPCError("offline")):
            with self.assertRaises(samsung_ipc.IPCError):
                samsung_ipc.control_power("off")


if __name__ == "__main__":
    unittest.main()
