#!/usr/bin/env python3
"""Exercise the capture script with no sudo, service, or hardware operations."""

import os
from pathlib import Path
import subprocess
import tempfile


def main():
    source = Path(__file__).with_name("check_graphics_tty.sh").read_text()
    with tempfile.TemporaryDirectory(prefix="legion-capture-test-") as directory:
        root = Path(directory)
        mock = root / "mock"
        mock.mkdir()
        dispatch = mock / "dispatch"
        dispatch.write_text('''#!/usr/bin/env bash
set -eu
name=${0##*/}
printf '%s %s\n' "$name" "$*" >> "$TEST_CALLS"
case "$name" in
  tty) printf '%s\n' "${TEST_TTY:-/dev/tty3}" ;;
  sudo)
    [[ $1 != -v ]] || exit 0
    exec "$@"
    ;;
  systemctl)
    case "$1" in
      is-active) echo "${TEST_DISPLAY_STATE:-active}" ;;
      stop) exit "${TEST_STOP_RESULT:-0}" ;;
      start) exit "${TEST_START_RESULT:-0}" ;;
    esac
    ;;
  legion_cli)
    [[ "$*" == '--donotexpecthwmon graphics-mode status --json' ]] || exit 99
    echo '{"selected_mode":"hybrid","active_clients":[]}'
    exit "${TEST_STATUS_RESULT:-0}"
    ;;
  systemd-analyze) echo 'HibernateMode=shutdown' ;;
  sleep) ;;
  *) exit 99 ;;
esac
''')
        dispatch.chmod(0o755)
        for name in ("tty", "sudo", "systemctl", "legion_cli", "systemd-analyze", "sleep"):
            (mock / name).symlink_to(dispatch)
        script = root / "check.sh"
        # Only redirect the immutable production CLI path to our fake executable.
        script.write_text(source.replace(
            "CLI=/run/current-system/sw/bin/legion_cli", f"CLI={mock / 'legion_cli'}"
        ))
        cases = [
            ("success", {}, "y\n", 0, True, True),
            ("cancel", {}, "n\n", 0, False, False),
            ("desktop refused", {"TEST_TTY": "/dev/pts/3"}, "y\n", 1, False, False),
            ("status failure recovers", {"TEST_STATUS_RESULT": "1"}, "y\n", 1, True, True),
            ("stop failure recovers", {"TEST_STOP_RESULT": "1"}, "y\n", 1, True, False),
            ("recovery failure reported", {"TEST_START_RESULT": "1"}, "y\n", 1, True, True),
            ("already stopped preserved", {"TEST_DISPLAY_STATE": "inactive"}, "y\n", 0, False, True),
            ("unexpected state refused", {"TEST_DISPLAY_STATE": "failed"}, "y\n", 1, False, False),
        ]
        for index, (name, extra, answer, expected, restarted, inspected) in enumerate(cases):
            state = root / f"state-{index}"
            calls = root / f"calls-{index}"
            env = dict(os.environ, PATH=f"{mock}:{os.environ['PATH']}",
                       XDG_STATE_HOME=str(state), TEST_CALLS=str(calls), **extra)
            result = subprocess.run(["bash", str(script)], input=answer, text=True,
                                    capture_output=True, env=env, timeout=5)
            assert result.returncode == expected, (name, result.stdout, result.stderr)
            events = calls.read_text()
            assert ("systemctl start display-manager.service" in events) == restarted, name
            assert ("legion_cli --donotexpecthwmon graphics-mode status --json" in events) == inspected, name
            assert "graphics-mode set" not in events, name
            assert "suspend" not in events.replace("systemd-suspend-then-hibernate.service", ""), name
            if inspected:
                logs = list(state.glob("legion-graphics-check/*.log"))
                assert len(logs) == 1, name
                assert '"selected_mode":"hybrid"' in logs[0].read_text(), name
                assert logs[0].stat().st_mode & 0o077 == 0, name
            print(f"PASS: {name}")


if __name__ == "__main__":
    main()
