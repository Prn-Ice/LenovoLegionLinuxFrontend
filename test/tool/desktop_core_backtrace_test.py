"""Retain GDB mappings when an independent all-thread backtrace fails."""

import os
import json
import shutil
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

    def test_collector_keeps_core_libraries_build_ids_and_hashes_after_gdb_error(self):
        with tempfile.TemporaryDirectory(prefix="collector failure ") as temporary:
            directory = Path(temporary)
            binary = directory / "bin"
            binary.mkdir()
            fixture = directory / "fixture"
            phase = fixture / "fuse"
            library = phase / "rootfs/usr/lib/fixtureapp"
            library.parent.mkdir(parents=True)
            library.write_bytes(b"\x7fELFfixture library bytes")
            (phase / "process.json").write_text(json.dumps({
                "pid": 1234, "executable": "/usr/lib/fixtureapp",
            }))
            scripts = {
                "id": "echo 0",
                "systemd-detect-virt": "echo kvm",
                "journalctl": "echo 'fixture journal'",
                "readelf": "echo 'Build ID: fixture-build-id'",
                "gdb": 'case "$*" in *"bt full"*) exit 7 ;; *) echo "/usr/lib/fixtureapp" ;; esac',
                "coredumpctl": 'for value in "$@"; do case "$value" in --output=*) echo core > "${value#--output=}" ;; esac; done; echo "fixture systemd report"',
                "cp": 'if [[ "$*" == *appimage-diagnostic* ]]; then exec "$REAL_CP" -a "$FIXTURE" "${@: -1}"; fi; exit 9',
            }
            for name, body in scripts.items():
                path = binary / name
                path.write_text("#!/bin/bash\n" + body + "\n")
                path.chmod(0o755)
            output = directory / "output"
            result = subprocess.run(
                ["bash", "control/test/appimage_core_diagnostic.sh", "collect", str(output), "134"],
                cwd=ROOT,
                env=os.environ | {"PATH": f"{binary}:{os.environ['PATH']}",
                                  "FIXTURE": str(fixture),
                                  "REAL_CP": shutil.which("cp")},
                text=True, capture_output=True, timeout=15, check=False,
            )
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertTrue((output / "fuse.core").is_file())
            self.assertTrue((output / "desktop/fuse/rootfs/usr/lib/fixtureapp").is_file())
            self.assertIn("maps_status=0", (output / "fuse-gdb-status.txt").read_text())
            self.assertIn("fixture-build-id", (output / "fuse-build-ids.txt").read_text())
            self.assertIn("raw_core_bytes=", (output / "fuse-core-size.txt").read_text())
            self.assertIn("fuse.core", (output / "evidence-hashes.txt").read_text())
            self.assertIn("qualification=134", (output / "collection-status.txt").read_text())


if __name__ == "__main__":
    unittest.main()
