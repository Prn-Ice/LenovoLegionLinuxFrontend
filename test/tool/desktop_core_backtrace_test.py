"""Retain GDB mappings when an independent all-thread backtrace fails."""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class DesktopCoreBacktraceTest(unittest.TestCase):
    def test_backtrace_error_does_not_skip_mappings_or_statuses(self):
        with tempfile.TemporaryDirectory(prefix="core evidence ") as temporary:
            directory = Path(temporary)
            gdb = directory / "gdb"
            gdb.write_text(
                '#!/bin/bash\n'
                'printf "%s\\n" "$*" >> "$CALLS"\n'
                'case "$*" in\n'
                '  *"bt full"*) echo "fixture backtrace error"; exit 7 ;;\n'
                '  *) echo "/usr/lib/fixture.so" ;;\n'
                'esac\n'
            )
            gdb.chmod(0o755)
            prefix = directory / "app"
            result = subprocess.run(
                ["bash", "-c", 'set -euo pipefail; source "$1"; '
                 'collect_backtrace fixture core "$2" /', "backtrace test",
                 str(ROOT / "control/test/desktop_core_backtrace.sh"), str(prefix)],
                env=os.environ | {"PATH": f"{directory}:{os.environ['PATH']}",
                                  "CALLS": str(directory / "calls")},
                text=True, capture_output=True, timeout=10, check=False,
            )
            self.assertEqual(result.returncode, 7, result.stderr)
            self.assertEqual(len((directory / "calls").read_text().splitlines()), 2)
            self.assertIn("fixture.so", (directory / "app-library-maps.txt").read_text())
            self.assertEqual((directory / "app-gdb-status.txt").read_text(),
                             "backtrace_status=7\nmaps_status=0\n")


if __name__ == "__main__":
    unittest.main()
