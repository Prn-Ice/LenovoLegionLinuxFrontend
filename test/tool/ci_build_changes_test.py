import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "ci_build_changes", Path(__file__).resolve().parents[2] / "tool/ci_build_changes.py"
)
assert SPEC and SPEC.loader
changes = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(changes)


class BuildChangesTest(unittest.TestCase):
    def test_documentation_only_skips_packaging(self):
        self.assertFalse(changes.needs_build(["README.md", "docs/nix.md", "AGENTS.md"]))

    def test_build_inputs_and_workflows_require_packaging(self):
        for path in [
            "lib/main.dart",
            "linux/CMakeLists.txt",
            "control/test/fixtures.nix",
            "telemetry/package.nix",
            "packaging/nix/frontend.nix",
            "assets/icon.svg",
            "tool/build_appimage.sh",
            "test/tool/ci_build_changes_test.py",
            "integration_test/app_test.dart",
            "pubspec.lock",
            "flake.nix",
            "flake.lock",
            ".github/workflows/ci.yml",
            "THIRD_PARTY_NOTICES.md",
        ]:
            with self.subTest(path=path):
                self.assertTrue(changes.needs_build(["README.md", path]))

    def test_rename_and_deletion_preserve_build_paths(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)

            def git(*args):
                return (
                    subprocess.run(
                        ["git", "-C", str(root), *args],
                        check=True,
                        capture_output=True,
                    )
                    .stdout.decode()
                    .strip()
                )

            git("init")
            git("config", "user.name", "CI test")
            git("config", "user.email", "test@example.invalid")
            (root / "lib").mkdir()
            (root / "lib/old.dart").write_text("original\n")
            git("add", ".")
            git("commit", "-m", "base")
            base = git("rev-parse", "HEAD")
            (root / "docs").mkdir()
            (root / "lib/old.dart").rename(root / "docs/old.md")
            git("add", "-A")
            git("commit", "-m", "move")
            result = subprocess.run(
                [sys.executable, str(Path(changes.__file__)), "--base", base],
                cwd=root,
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.stdout, "build=true\n")
            (root / "docs/old.md").unlink()
            (root / "lib/deleted.dart").write_text("remove me\n")
            git("add", "-A")
            git("commit", "-m", "new source")
            base = git("rev-parse", "HEAD")
            (root / "lib/deleted.dart").unlink()
            git("add", "-A")
            git("commit", "-m", "delete")
            result = subprocess.run(
                [sys.executable, str(Path(changes.__file__)), "--base", base],
                cwd=root,
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.stdout, "build=true\n")

    def test_main_and_tag_calls_run_all_checks(self):
        result = subprocess.run(
            [sys.executable, str(Path(changes.__file__))],
            check=True,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.stdout, "build=true\n")


if __name__ == "__main__":
    unittest.main()
