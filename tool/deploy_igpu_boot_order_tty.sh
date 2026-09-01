#!/usr/bin/env bash
set -euo pipefail

CLI="/run/current-system/sw/bin/legion_cli"
FLAKE="/home/prnice/Dotfiles/nixos-flaky-tests#nixos"

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

tty_path=$(tty 2>/dev/null || true)
case "$tty_path" in
  /dev/tty[0-9]*) ;;
  *) fail "Run this script from a Linux virtual console such as Ctrl+Alt+F3, not $tty_path." ;;
esac

[[ -x "$CLI" ]] || fail "Validated CLI is unavailable at $CLI."
[[ $("$CLI" --donotexpecthwmon graphics-mode status) == "hybrid-igpu-only" ]] ||
  fail "Expected Hybrid iGPU-only to be selected before deployment."

sudo -v
sudo nixos-rebuild boot --flake "$FLAKE"

printf '\nCurrent graphics state:\n'
sudo "$CLI" --donotexpecthwmon graphics-mode status --json
printf '\nInstalled boot system:\n'
readlink -f /nix/var/nix/profiles/system
printf '\nReboot to validate reconciliation before CDI and the display manager.\n'
