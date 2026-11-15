"""Check runtime dependency failures and source attribution before packaging."""

import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "bundle_appimage_runtime",
    Path(__file__).resolve().parents[2] / "tool/bundle_appimage_runtime.py",
)
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


class RuntimeTest(unittest.TestCase):
    def test_repeated_package_attribution_stays_a_package_name(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source.so"
            source.write_bytes(b"library")
            bundle = runtime.RuntimeBundle(root / "app", root / "inputs")
            bundle.packages["fixture"] = {
                "version": "1",
                "source": "fixture",
                "source_version": "1",
            }
            target = bundle.bundle / "lib/test.so"
            bundle.copy(source, target, package="fixture")
            self.assertEqual(
                bundle.files[str(target.relative_to(bundle.appdir))]["package"],
                "fixture",
            )

    def test_source_changed_after_linking_cannot_be_archived_as_the_original(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            bundle = runtime.RuntimeBundle(root / "app", root / "inputs")
            sources = bundle.inputs / "sources/example"
            sources.mkdir(parents=True)
            archive = sources / "example.tar.gz"
            archive.write_bytes(b"original source")
            bundle.sources["example"] = {
                "version": "1",
                "archives": {archive.name: runtime.sha256(archive)},
            }
            archive.write_bytes(b"changed source")
            with self.assertRaisesRegex(ValueError, "Source archives changed"):
                bundle.finish()

    def test_missing_dependency_stops_packaging(self):
        with self.assertRaisesRegex(ValueError, "libgtk-3"):
            runtime.dependencies("libgtk-3.so.0 => not found\n")

    def test_dependency_paths_preserve_spaces(self):
        self.assertEqual(
            runtime.dependencies(
                " libgtk-3.so.0 => /app with spaces/libgtk-3.so.0 (0x1234)\n"
            ),
            {"libgtk-3.so.0": Path("/app with spaces/libgtk-3.so.0")},
        )

    def test_conflicting_libraries_cannot_silently_replace_a_bundle_file(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source, target = root / "source.so", root / "target.so"
            source.write_text("new")
            target.write_text("existing")
            bundle = runtime.RuntimeBundle(root / "app", root / "inputs")
            with (
                patch.object(bundle, "owner", return_value="test-package"),
                self.assertRaisesRegex(ValueError, "Conflicting"),
            ):
                bundle.copy(source, target)
            self.assertEqual(target.read_text(), "existing")

    def test_copy_retains_package_and_hash_for_source_pairing(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source.so"
            source.write_text("library")
            bundle = runtime.RuntimeBundle(root / "app", root / "inputs")
            target = bundle.bundle / "lib/test.so"
            with patch.object(bundle, "owner", return_value="test-package"):
                bundle.copy(source, target)
            entry = bundle.files[str(target.relative_to(bundle.appdir))]
            self.assertEqual(entry["package"], "test-package")
            self.assertEqual(entry["sha256"], runtime.sha256(source))


if __name__ == "__main__":
    unittest.main()
