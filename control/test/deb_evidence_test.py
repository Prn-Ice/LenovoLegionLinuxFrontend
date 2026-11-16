"""Keep Debian GUI evidence and the original result after a failed VM check."""

import shlex
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path


class DebianEvidenceTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="deb evidence ")
        self.addCleanup(temporary.cleanup)
        self.home = Path(temporary.name)
        self.archive = self.home / "deb-qualification.tar.gz"
        source = Path(__file__).with_name("qualify_deb.sh").read_text()
        start = source.index("finish_qualification() {")
        end = source.index("\n}\n", start) + 3
        # Run the real collector against local files, never /root or a VM user.
        self.collector = source[start:end].replace(
            "/home/approved", shlex.quote(str(self.home))
        ).replace("/root/deb-qualification.tar.gz", shlex.quote(str(self.archive)))

    def collect(self, original_status, *, archive_error=False):
        script = "set -euo pipefail\n"
        if archive_error:
            script += "timeout() { return 33; }\n"
        script += self.collector + "\ntrap finish_qualification EXIT\n"
        return subprocess.run(
            ["bash", "-c", script + f"exit {original_status}\n"],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )

    def test_partial_failure_keeps_gui_logs_screenshots_and_diagnostics(self):
        names = {
            "deb-gui.log",
            "desktop-frame-Debian package.png",
            "desktop-diagnostics-Debian package.txt",
        }
        for name in names:
            (self.home / name).write_text("synthetic failure evidence\n")
        result = self.collect(23)
        self.assertEqual(result.returncode, 23, result.stderr)
        with tarfile.open(self.archive) as archive:
            self.assertEqual(set(archive.getnames()), names)

    def test_success_keeps_every_file_required_by_release_validation(self):
        names = {
            "deb-versions.txt",
            "deb-gui.log",
            "deb-release-manifest.json",
            "deb-os-release",
            "deb-checks.json",
        }
        for name in names:
            (self.home / name).write_text("synthetic release evidence\n")
        result = self.collect(0)
        self.assertEqual(result.returncode, 0, result.stderr)
        with tarfile.open(self.archive) as archive:
            self.assertEqual(set(archive.getnames()), names)

    def test_archive_errors_preserve_failures_but_do_not_report_success(self):
        for original, expected in [(23, 23), (0, 33)]:
            with self.subTest(original_status=original):
                result = self.collect(original, archive_error=True)
                self.assertEqual(result.returncode, expected, result.stderr)


if __name__ == "__main__":
    unittest.main()
