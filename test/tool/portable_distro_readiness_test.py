"""Exercise cloud-init readiness with local SSH and cloud-init fakes."""

import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "tool/portable_distro_readiness.sh"


class PortableDistroReadinessTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(
            prefix="portable distro readiness with spaces "
        )
        self.addCleanup(self.temporary.cleanup)
        self.fixture = Path(self.temporary.name)
        self.helper = self.fixture / "helper with spaces.sh"
        self.helper.write_bytes(HELPER.read_bytes())
        self.ssh_calls = self.fixture / "ssh calls"
        self.cloud_init_calls = self.fixture / "cloud init calls"
        self.transport_state = self.fixture / "transport state"
        self.fake_ssh = self.fixture / "fake ssh"
        self.fake_cloud_init = self.fixture / "cloud-init"
        self._write_executable(
            self.fake_ssh,
            """#!/usr/bin/env bash
set -eu
printf '%s\\0' "$@" >> "$FAKE_SSH_CALLS"
printf '\\n' >> "$FAKE_SSH_CALLS"
case "$FAKE_SSH_MODE" in
  reset-once)
    if [[ ! -e $FAKE_TRANSPORT_STATE ]]; then
      touch "$FAKE_TRANSPORT_STATE"
      echo 'kex_exchange_identification: read: Connection reset by peer' >&2
      exit 255
    fi
    ;;
  hang)
    trap '' TERM
    while true; do read -r -t 1 || true; done
    ;;
esac
remote_command="${!#}"
exec bash -c "$remote_command"
""",
        )
        self._write_executable(
            self.fake_cloud_init,
            """#!/usr/bin/env bash
set -eu
printf '%s\\n' "$*" >> "$FAKE_CLOUD_INIT_CALLS"
case "$FAKE_CLOUD_INIT_MODE" in
  success) echo 'status: done' ;;
  critical) echo 'status: error' >&2; exit 1 ;;
  recoverable) echo 'status: degraded done' >&2; exit 2 ;;
  remote-timeout) exit 124 ;;
  remote-255)
    echo 'cloud-init failed after Connection reset by peer while reading metadata' >&2
    exit 255
    ;;
esac
""",
        )

    @staticmethod
    def _write_executable(path, contents):
        path.write_text(contents)
        path.chmod(0o755)

    def run_readiness(self, seconds, *, ssh_mode="execute", cloud_init_mode="success"):
        environment = os.environ | {
            "FAKE_SSH_CALLS": str(self.ssh_calls),
            "FAKE_SSH_MODE": ssh_mode,
            "FAKE_TRANSPORT_STATE": str(self.transport_state),
            "FAKE_CLOUD_INIT_CALLS": str(self.cloud_init_calls),
            "FAKE_CLOUD_INIT_MODE": cloud_init_mode,
            "PATH": f"{self.fixture}{os.pathsep}{os.environ['PATH']}",
        }
        return subprocess.run(
            [
                "bash",
                "-c",
                'source "$1"; shift; wait_for_cloud_init "$@"',
                "readiness test",
                str(self.helper),
                str(seconds),
                str(self.fake_ssh),
                "--fixture-option",
                "value with spaces",
            ],
            text=True,
            capture_output=True,
            check=False,
            timeout=seconds + 5,
            env=environment,
        )

    def ssh_remote_commands(self):
        if not self.ssh_calls.exists():
            return []
        calls = self.ssh_calls.read_bytes().splitlines()
        return [call.split(b"\0")[-2].decode() for call in calls]

    def cloud_init_call_count(self):
        if not self.cloud_init_calls.exists():
            return 0
        return len(self.cloud_init_calls.read_text().splitlines())

    def test_transport_reset_then_success_executes_cloud_init(self):
        result = self.run_readiness(5, ssh_mode="reset-once")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "status: done\n")
        self.assertIn("kex_exchange_identification", result.stderr)
        self.assertIn("retrying", result.stderr)
        self.assertEqual(self.cloud_init_call_count(), 1)
        remote_commands = self.ssh_remote_commands()
        self.assertGreaterEqual(len(remote_commands), 2)
        timeout_values = [
            int(
                re.fullmatch(
                    r"timeout ([0-9]+) cloud-init status --wait", command
                ).group(1)
            )
            for command in remote_commands
        ]
        self.assertTrue(all(0 < value <= 5 for value in timeout_values))
        self.assertEqual(timeout_values, sorted(timeout_values, reverse=True))
        self.assertIn(b"value with spaces\0", self.ssh_calls.read_bytes())

    def test_cloud_init_failures_return_without_retry(self):
        for mode, status in [("critical", 1), ("recoverable", 2)]:
            with self.subTest(mode=mode):
                result = self.run_readiness(5, cloud_init_mode=mode)
                self.assertEqual(result.returncode, status, result.stderr)
                self.assertEqual(self.cloud_init_call_count(), 1)
                self.cloud_init_calls.unlink()
                self.ssh_calls.unlink()

    def test_remote_timeout_returns_without_retry(self):
        result = self.run_readiness(5, cloud_init_mode="remote-timeout")

        self.assertEqual(result.returncode, 124, result.stderr)
        self.assertIn("Timed out", result.stderr)
        self.assertEqual(self.cloud_init_call_count(), 1)
        self.assertEqual(len(self.ssh_remote_commands()), 1)

    def test_nontransport_status_255_is_not_retried(self):
        result = self.run_readiness(5, cloud_init_mode="remote-255")

        self.assertEqual(result.returncode, 255, result.stderr)
        self.assertIn("Connection reset by peer", result.stderr)
        self.assertNotIn("retrying", result.stderr)
        self.assertEqual(self.cloud_init_call_count(), 1)
        self.assertEqual(len(self.ssh_remote_commands()), 1)

    def test_zero_budget_does_not_start_ssh(self):
        result = self.run_readiness(0)

        self.assertEqual(result.returncode, 124, result.stderr)
        self.assertIn("deadline expired", result.stderr)
        self.assertFalse(self.ssh_calls.exists())

    def test_hanging_ssh_is_stopped_by_local_deadline(self):
        result = self.run_readiness(1, ssh_mode="hang")

        self.assertEqual(result.returncode, 124, result.stderr)
        self.assertIn("Timed out", result.stderr)
        self.assertFalse(self.cloud_init_calls.exists())


if __name__ == "__main__":
    unittest.main()
