"""Keep failure evidence and the original result before disposable VM cleanup."""

import os
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class PortableDistroEvidenceTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="desktop evidence ")
        self.addCleanup(self.temporary.cleanup)
        self.home = Path(self.temporary.name)
        self.bin = self.home / "bin"
        self.bin.mkdir()
        self.environment = os.environ | {
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "EVENTS": str(self.home / "events"),
        }

    def fake(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/bash\n" + body + "\n")
        path.chmod(0o755)

    def run_shell(self, script, *arguments, **environment):
        return subprocess.run(
            ["bash", "-c", "set -euo pipefail\n" + script, "evidence test", *map(str, arguments)],
            env=self.environment | environment, capture_output=True, text=True,
            timeout=10, check=False,
        )

    def retrieve(self, primary, *, journal=0, transfer=0):
        self.fake("ssh", 'echo journal >> "$EVENTS"; exit "$JOURNAL"')
        self.fake("scp", 'echo archive >> "$EVENTS"; exit "$TRANSFER"')
        return self.run_shell(
            'source "$1"; trap \'echo cleanup >> "$EVENTS"\' EXIT; '
            'retrieve_distro_evidence "$2" appimage-qualification.tar.gz "$3" 2222 -i "key with spaces"',
            ROOT / "tool/portable_distro_evidence.sh", self.home, primary,
            JOURNAL=str(journal), TRANSFER=str(transfer),
        )

    def test_failed_qualification_retrieves_archive_before_cleanup(self):
        result = self.retrieve(134)
        self.assertEqual(result.returncode, 134, result.stderr)
        self.assertEqual((self.home / "events").read_text().splitlines(),
                         ["journal", "archive", "cleanup"])
        self.assertIn("qualification=134", (self.home / "qualification-status.txt").read_text())

    def test_collection_errors_do_not_replace_the_original_failure(self):
        result = self.retrieve(23, journal=7, transfer=9)
        self.assertEqual(result.returncode, 23, result.stderr)
        self.assertEqual((self.home / "events").read_text().splitlines(),
                         ["journal", "archive", "cleanup"])
        status = (self.home / "qualification-status.txt").read_text()
        self.assertIn("journal=7", status)
        self.assertIn("archive=9", status)

    def test_missing_archive_does_not_turn_success_into_a_pass(self):
        result = self.retrieve(0, transfer=9)
        self.assertEqual(result.returncode, 9, result.stderr)

    def archive(self, primary, *, collection=0):
        self.fake("dpkg-query", 'echo versions; exit "$COLLECTION"')
        self.fake("lscpu", "echo 'fixture CPU'")
        release = self.home / "AppImage with spaces"
        release.mkdir()
        (release / "legion-frontend-fixture.json").write_text("{}\n")
        (self.home / "appimage-gui-fuse.log").write_text("LLVM fixture failure\n")
        (self.home / "appimage-runtime-fuse.txt").write_text("fixture maps\n")
        return self.run_shell(
            'source "$1"; retain_appimage_evidence "$2" "$2/evidence.tar.gz" "$3"',
            ROOT / "control/test/appimage_evidence.sh", self.home, primary,
            COLLECTION=str(collection),
        )

    def test_partial_gui_evidence_is_archived_after_failure(self):
        result = self.archive(134, collection=7)
        self.assertEqual(result.returncode, 134, result.stderr)
        with tarfile.open(self.home / "evidence.tar.gz") as archive:
            self.assertIn("appimage-gui-fuse.log", archive.getnames())
            self.assertIn("appimage-runtime-fuse.txt", archive.getnames())
            self.assertNotIn("appimage-gui-extracted.log", archive.getnames())
            self.assertIn("fixture CPU", archive.extractfile("appimage-cpu.txt").read().decode())
            self.assertIn("versions=7", archive.extractfile("appimage-evidence-status.txt").read().decode())

    def test_collection_failure_is_reported_after_successful_qualification(self):
        result = self.archive(0, collection=7)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.home / "evidence.tar.gz").exists())

    def test_archive_failure_preserves_the_application_failure(self):
        self.fake("tar", "exit 33")
        result = self.archive(134)
        self.assertEqual(result.returncode, 134, result.stderr)
        self.assertTrue((self.home / "appimage-cpu.txt").exists())

    def test_archive_failure_is_reported_after_successful_qualification(self):
        self.fake("tar", "exit 33")
        result = self.archive(0)
        self.assertEqual(result.returncode, 33, result.stderr)


if __name__ == "__main__":
    unittest.main()
