import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "tool/portable_distro_readiness.sh"


def write_fake_ssh(directory, mode):
    script = directory / "fake-ssh"
    script.write_text(
        "#!/usr/bin/env bash\n"
        "set -eu\n"
        f"case {mode!r} in\n"
        "  reset-once)\n"
        "    if [[ ! -e \"$FAKE_SSH_MARKER\" ]]; then touch \"$FAKE_SSH_MARKER\"; "
        "printf '%s\\n' 'kex_exchange_identification: read: Connection reset by peer' >&2; exit 255; fi\n"
        "    ;;&\n"
        "  command-failure) printf 'remote failure\\n__LLLF_CLOUD_INIT_STATUS__42\\n'; exit 42;;\n"
        "  hang) exec sleep 30;;\n"
        "esac\n"
        "printf 'status: done\\n__LLLF_CLOUD_INIT_STATUS__0\\n'\n"
    )
    script.chmod(0o755)
    return script


def run_helper(fake_ssh, seconds=5, environment=None):
    return subprocess.run(
        ["bash", "-c", f"source {HELPER}; wait_for_cloud_init {seconds} {fake_ssh}"],
        text=True,
        capture_output=True,
        timeout=seconds + 3,
        check=False,
        env=environment,
    )


class PortableDistroReadinessTest(unittest.TestCase):
    def test_retries_one_transport_reset_then_succeeds(self):
        with tempfile.TemporaryDirectory() as directory:
            tmp_path = Path(directory)
            fake = write_fake_ssh(tmp_path, "reset-once")
            result = run_helper(
                fake,
                environment=os.environ | {"FAKE_SSH_MARKER": str(tmp_path / "marker")},
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "status: done")


    def test_preserves_immediate_nontransport_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            fake = write_fake_ssh(Path(directory), "command-failure")
            result = run_helper(fake)
            self.assertEqual(result.returncode, 42)
            self.assertIn("remote failure", result.stderr)


    def test_hanging_ssh_is_bounded_by_readiness_deadline(self):
        with tempfile.TemporaryDirectory() as directory:
            fake = write_fake_ssh(Path(directory), "hang")
            result = run_helper(fake, seconds=1)
            self.assertNotEqual(result.returncode, 0)
