#!/usr/bin/env python3
"""Exercise the setup launcher without sudo, Nix builds, or profile changes."""

import os
from pathlib import Path
import subprocess
import tempfile


def main():
    script = Path(__file__).with_name("setup_next_boot_graphics.sh").resolve()
    with tempfile.TemporaryDirectory(prefix="legion-setup-test-") as directory:
        root = Path(directory)
        mock = root / "mock"
        mock.mkdir()
        dispatch = mock / "dispatch"
        dispatch.write_text('''#!/usr/bin/env bash
set -eu
name=${0##*/}
printf '%s %s\n' "$name" "$*" >> "$TEST_CALLS"
case "$name" in
  tty) echo "${TEST_TTY:-/dev/pts/3}" ;;
  systemd-inhibit)
    while [[ $1 != bash ]]; do shift; done
    exec "$@"
    ;;
  nix)
    case "$1" in
      eval)
        case "${!#}" in
          *.nextBootGraphics) echo "${TEST_ENABLED:-true}" ;;
          *.tags) echo "${TEST_TAGS:-[]}" ;;
          *) exit 99 ;;
        esac
        ;;
      build)
        [[ ${TEST_BUILD_FAIL:-0} == 0 ]] || exit 1
        echo "$TEST_BUILT"
        ;;
      *) exit 99 ;;
    esac
    ;;
  sudo)
    case "$1" in
      -v) exit 0 ;;
      test)
        [[ "$*" == 'test ! -e /var/lib/legion-graphics-boot/request.json' ]] || exit 99
        [[ ${TEST_PENDING:-0} == 0 ]]
        ;;
      nixos-rebuild) exec "$@" ;;
      *) exit 99 ;;
    esac
    ;;
  nixos-rebuild)
    [[ $1 == boot ]] || exit 99
    [[ ${TEST_INSTALL_FAIL:-0} == 0 ]] || exit 1
    : > "$TEST_INSTALLED"
    ;;
  readlink)
    case "${!#}" in
      /run/current-system)
        if [[ -e $TEST_INSTALLED && ${TEST_RUNTIME_CHANGED:-0} == 1 ]]; then
          echo /nix/store/unexpected-nixos-system-nixos
        else
          echo /nix/store/original-nixos-system-nixos
        fi
        ;;
      /nix/var/nix/profiles/system) echo "${TEST_PROFILE:-$TEST_BUILT}" ;;
      *) exit 99 ;;
    esac
    ;;
  cat)
    [[ $1 == /proc/sys/kernel/random/boot_id ]] || exit 99
    echo 11111111-1111-4111-8111-111111111111
    ;;
  *) exit 99 ;;
esac
''')
        dispatch.chmod(0o755)
        for name in ("tty", "systemd-inhibit", "nix", "sudo", "nixos-rebuild", "readlink", "cat"):
            (mock / name).symlink_to(dispatch)
        cases = [
            ("success", {}, "y\n", 0, True),
            ("cancel", {}, "n\n", 0, False),
            ("nonterminal refused", {"TEST_TTY": "not a tty"}, "y\n", 1, False),
            ("disabled configuration refused", {"TEST_ENABLED": "false"}, "y\n", 1, False),
            ("specialisation refused", {"TEST_TAGS": '["no-nvidia"]'}, "y\n", 1, False),
            ("build failure", {"TEST_BUILD_FAIL": "1"}, "y\n", 1, False),
            ("request state needs review", {"TEST_PENDING": "1"}, "y\n", 1, False),
            ("installation failure", {"TEST_INSTALL_FAIL": "1"}, "y\n", 1, True),
            ("unexpected profile", {"TEST_PROFILE": "/nix/store/other"}, "y\n", 1, True),
            ("unexpected runtime change", {"TEST_RUNTIME_CHANGED": "1"}, "y\n", 1, True),
        ]
        for index, (name, extra, answer, expected, installs) in enumerate(cases):
            calls = root / f"calls-{index}"
            state = root / f"state-{index}"
            env = dict(os.environ, PATH=f"{mock}:{os.environ['PATH']}",
                       XDG_STATE_HOME=str(state), TEST_CALLS=str(calls),
                       TEST_BUILT="/nix/store/reviewed-nixos-system-nixos",
                       TEST_INSTALLED=str(root / f"installed-{index}"), **extra)
            result = subprocess.run(["bash", str(script)], input=answer, text=True,
                                    capture_output=True, env=env, timeout=5)
            assert result.returncode == expected, (name, result.stdout, result.stderr)
            events = calls.read_text()
            assert ("nixos-rebuild boot " in events) == installs, (name, events)
            assert "nixos-rebuild switch" not in events, name
            assert "graphics-mode set" not in events, name
            assert "systemctl reboot" not in events, name
            if installs:
                assert "?rev=384070f2ec75d95bee958f0f33545b5ecd73a23b#nixos" in events, name
                assert "--no-write-lock-file" in events, name
                assert "--what=sleep:shutdown --mode=block" in events, name
            logs = list(state.glob("legion-graphics-setup/*.log"))
            if name != "nonterminal refused":
                assert len(logs) == 1, (name, result.stdout)
                assert "Log saved:" in logs[0].read_text(), name
                assert logs[0].stat().st_mode & 0o077 == 0, name
            print(f"PASS: {name}")


if __name__ == "__main__":
    main()
