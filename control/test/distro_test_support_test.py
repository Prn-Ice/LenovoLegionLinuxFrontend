"""Bound fixture commands and stop their children after a timeout."""

import os
import re
import shlex
import signal
import sys
import unittest
import uuid
from pathlib import Path

from distro_test_support import LocalMachine


class LocalMachineTest(unittest.TestCase):
    def test_returns_the_command_status_and_output(self):
        code, output = LocalMachine().execute("printf fixture-output; exit 7")
        self.assertEqual(code, 7)
        self.assertEqual(output, "fixture-output")

    def test_timeout_stops_the_owned_child_and_retains_output(self):
        marker = "fixture-timeout-" + uuid.uuid4().hex
        command = (
            shlex.quote(sys.executable)
            + " -u -c "
            + shlex.quote("import signal; signal.pause()")
            + " "
            + marker
            + ' & child=$!; printf "OWNED_PID=%s\\n" "$child"; wait "$child"'
        )
        child = None
        try:
            with self.assertRaisesRegex(
                AssertionError, "Command timed out after 1 seconds"
            ) as raised:
                LocalMachine().execute(command, timeout=1)
            match = re.search(r"(?m)^OWNED_PID=(\d+)$", str(raised.exception))
            self.assertIsNotNone(match, str(raised.exception))
            child = int(match[1])
            status = Path(f"/proc/{child}/stat")
            try:
                state = status.read_text().split(") ")[1][0]
            except FileNotFoundError:
                state = None
            # An orphan can remain a zombie briefly before init reaps it.
            self.assertIn(state, (None, "Z"))
        finally:
            if child is not None:
                cmdline = Path(f"/proc/{child}/cmdline")
                try:
                    if marker.encode() in cmdline.read_bytes():
                        os.kill(child, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                except FileNotFoundError:
                    pass


if __name__ == "__main__":
    unittest.main()
