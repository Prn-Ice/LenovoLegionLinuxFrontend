"""Check frontend CMake targets and installation without building Flutter."""

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class DefaultHelperBuildTest(unittest.TestCase):
    def test_default_build_and_old_caches_bundle_only_the_privileged_control_helper(self):
        for cache in [
            [],
            [
                "-DBUILD_PORTABLE_CONTROL_HELPER=OFF",
                "-DBUILD_LEGION_CONTROL_SERVICE=ON",
            ],
        ]:
            with self.subTest(cache=cache), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                linux = root / "linux"
                flutter = linux / "flutter"
                runner = linux / "runner"
                modules = root / "modules"
                flutter.mkdir(parents=True)
                runner.mkdir()
                modules.mkdir()
                for name in ["CMakeLists.txt", "portable_helper_install.cmake.in"]:
                    shutil.copyfile(ROOT / "linux" / name, linux / name)
                for name in ["telemetry", "control", "packaging"]:
                    (root / name).symlink_to(ROOT / name, target_is_directory=True)
                # Only external Flutter and pkg-config dependencies are stubbed.
                # The frontend and native target/install declarations are real.
                (flutter / "CMakeLists.txt").write_text(
                    "add_custom_target(flutter_assemble)\n"
                    'set(FLUTTER_ROOT "/unused-sdk")\n'
                    'set(FLUTTER_ICU_DATA_FILE "${CMAKE_CURRENT_LIST_FILE}" PARENT_SCOPE)\n'
                    'set(FLUTTER_LIBRARY "${CMAKE_CURRENT_LIST_FILE}" PARENT_SCOPE)\n'
                )
                (flutter / "generated_plugins.cmake").write_text("")
                (runner / "runner.cc").write_text("int main() { return 0; }\n")
                (runner / "CMakeLists.txt").write_text(
                    "add_executable(${BINARY_NAME} runner.cc)\n"
                )
                (modules / "FindPkgConfig.cmake").write_text(
                    "set(PkgConfig_FOUND TRUE)\n"
                    "function(pkg_check_modules prefix)\n"
                    "  add_library(PkgConfig::${prefix} INTERFACE IMPORTED GLOBAL)\n"
                    "endfunction()\n"
                )
                build = root / "build"
                configured = subprocess.run(
                    [
                        "cmake",
                        "-S",
                        str(linux),
                        "-B",
                        str(build),
                        f"-DCMAKE_MODULE_PATH={modules}",
                        *cache,
                    ],
                    check=False,
                    text=True,
                    capture_output=True,
                )
                self.assertEqual(
                    configured.returncode, 0, configured.stdout + configured.stderr
                )
                targets = subprocess.check_output(
                    ["cmake", "--build", str(build), "--target", "help"], text=True
                )
                self.assertIn("legion_portable_control", targets)
                self.assertNotIn("legion_control_service", targets)
                install = (build / "cmake_install.cmake").read_text()
                self.assertIn("/libexec/legion-portable-control", install)
                self.assertNotIn("legion-control.service", install)


if __name__ == "__main__":
    unittest.main()
