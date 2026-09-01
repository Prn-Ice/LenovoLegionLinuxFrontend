#!/usr/bin/env bash
set -euo pipefail

CLI="/run/current-system/sw/bin/legion_cli"
RECONCILE_UNIT="legion-graphics-reconcile.service"
DISPLAY_UNIT="display-manager.service"
DROPIN_DIR="/run/systemd/system/${RECONCILE_UNIT}.d"
DROPIN="${DROPIN_DIR}/lllf-timeout-test.conf"
STARTED_AT=$(date --iso-8601=seconds)
LOG="/tmp/lllf-reconcile-timeout-${STARTED_AT//:/-}.log"
dropin_installed=0
display_manager_stopped=0

exec > >(tee -a "$LOG") 2>&1

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

# shellcheck disable=SC2329 # Invoked by the EXIT trap.
cleanup() {
  local status=$?
  local restore_status=0
  trap - EXIT
  set +e

  if [[ "$dropin_installed" -eq 1 ]]; then
    sudo rm -f "$DROPIN" || restore_status=1
    sudo rmdir --ignore-fail-on-non-empty "$DROPIN_DIR" || restore_status=1
    sudo systemctl daemon-reload || restore_status=1
  fi

  sudo systemctl reset-failed "$RECONCILE_UNIT" "$DISPLAY_UNIT" || restore_status=1
  sudo systemctl start "$RECONCILE_UNIT" || restore_status=1
  if [[ "$display_manager_stopped" -eq 1 ]]; then
    sudo systemctl start "$DISPLAY_UNIT" || restore_status=1
    display_manager_stopped=0
  fi

  printf '\nRestored service state:\n'
  systemctl --no-pager show "$RECONCILE_UNIT" "$DISPLAY_UNIT" \
    --property=Id \
    --property=ActiveState \
    --property=SubState \
    --property=Result \
    --property=ExecMainStatus
  printf 'Evidence log: %s\n' "$LOG"

  if [[ "$restore_status" -ne 0 ]]; then
    printf 'ERROR: Normal service restoration failed. Keep using this TTY and inspect the evidence log.\n' >&2
    status=1
  fi
  exit "$status"
}

tty_path=$(tty 2>/dev/null || true)
case "$tty_path" in
  /dev/tty[0-9]*) ;;
  *) fail "Run this script from a Linux virtual console such as Ctrl+Alt+F3, not $tty_path." ;;
esac

[[ -x "$CLI" ]] || fail "Validated CLI is unavailable at $CLI."
[[ $("$CLI" --donotexpecthwmon graphics-mode status) == "hybrid" ]] ||
  fail "Expected Hybrid before the timeout probe."
graphics_state=$("$CLI" --donotexpecthwmon graphics-mode status --json)
[[ "$graphics_state" == *'"effective_dgpu_state": "attached"'* ]] ||
  fail "Expected an attached dGPU before the timeout probe."
[[ "$graphics_state" == *'"reconciliation": "settled"'* ]] ||
  fail "Expected settled graphics topology before the timeout probe."
systemctl is-active --quiet "$DISPLAY_UNIT" || fail "The display manager must be active before the probe."
[[ ! -e "$DROPIN" ]] || fail "Runtime timeout test drop-in already exists at $DROPIN."

printf 'Starting reconciliation timeout probe at %s\n' "$STARTED_AT"
printf 'Evidence log: %s\n' "$LOG"
printf 'No graphics policy write will be requested.\n'
sudo -v
trap cleanup EXIT

sudo systemctl stop "$DISPLAY_UNIT"
display_manager_stopped=1
systemctl --user stop graphical-session.target plasma-workspace-wayland.target

while read -r session_id _; do
  session_type=$(loginctl show-session "$session_id" --property=Type --value 2>/dev/null || true)
  if [[ "$session_type" == "wayland" || "$session_type" == "x11" ]]; then
    sudo loginctl terminate-session "$session_id"
  fi
done < <(loginctl list-sessions --no-legend)

sleep 5

if systemctl --user is-active --quiet plasma-kwin_wayland.service; then
  fail "The graphical session did not stop before the timeout probe."
fi

sudo systemctl stop "$RECONCILE_UNIT"

printf '[Service]\nTimeoutStartSec=1ms\n' |
  sudo install -D -m 0644 /dev/stdin "$DROPIN"
dropin_installed=1
sudo systemctl daemon-reload

set +e
sudo systemctl start "$DISPLAY_UNIT"
start_result=$?
set -e

reconcile_result=$(systemctl show "$RECONCILE_UNIT" --property=Result --value)
display_state=$(systemctl is-active "$DISPLAY_UNIT" 2>/dev/null || true)

printf '\nTimeout probe state:\n'
systemctl --no-pager show "$RECONCILE_UNIT" "$DISPLAY_UNIT" \
  --property=Id \
  --property=ActiveState \
  --property=SubState \
  --property=Result \
  --property=ExecMainStatus
printf '\nTimeout journal:\n'
journalctl -b --since "$STARTED_AT" --no-pager \
  -u "$RECONCILE_UNIT" \
  -u "$DISPLAY_UNIT"

[[ "$start_result" -ne 0 ]] || fail "Display manager start unexpectedly succeeded."
[[ "$reconcile_result" == "timeout" ]] ||
  fail "Expected reconciliation Result=timeout, got $reconcile_result."
[[ "$display_state" != "active" ]] || fail "Display manager did not fail closed."

printf '\nPASS: reconciliation timed out and the display manager remained stopped.\n'
