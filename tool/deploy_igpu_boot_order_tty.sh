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

if systemctl is-active --quiet display-manager.service; then
  fail "Stop the display manager before deploying the boot-order fix."
fi

sudo -v
sudo nixos-rebuild switch --flake "$FLAKE"
sudo systemctl restart legion-graphics-reconcile.service
sudo systemctl restart nvidia-container-toolkit-cdi-generator.service

printf '\nGraphics reconciliation:\n'
sudo "$CLI" --donotexpecthwmon graphics-mode status --json
printf '\nService state:\n'
systemctl --no-pager --full status \
  legion-graphics-reconcile.service \
  nvidia-container-toolkit-cdi-generator.service
