#!/usr/bin/env bash
set -euo pipefail

DISPLAY_UNIT="display-manager.service"
STARTED_AT=$(date --iso-8601=seconds)
LOG="/tmp/lllf-recover-plasma-${STARTED_AT//:/-}.log"
display_manager_stopped=0

exec > >(tee -a "$LOG") 2>&1

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

# shellcheck disable=SC2329 # Invoked by the EXIT trap.
cleanup() {
  local status=$?
  trap - EXIT
  if [[ "$display_manager_stopped" -eq 1 ]]; then
    printf '\nStarting the display manager.\n'
    if sudo systemctl start "$DISPLAY_UNIT"; then
      display_manager_stopped=0
    else
      printf 'ERROR: Display manager recovery failed. Stay on this TTY and inspect %s.\n' "$LOG" >&2
      status=1
    fi
  fi
  printf 'Evidence log: %s\n' "$LOG"
  exit "$status"
}

tty_path=$(tty 2>/dev/null || true)
case "$tty_path" in
  /dev/tty[0-9]*) ;;
  *) fail "Run this script from a Linux virtual console such as Ctrl+Alt+F3, not $tty_path." ;;
esac

printf 'Recovering the Plasma graphical session at %s\n' "$STARTED_AT"
printf 'No graphics policy write will be requested.\n'
printf 'Evidence log: %s\n' "$LOG"
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

systemctl --user reset-failed
sleep 5

if systemctl --user is-active --quiet plasma-kwin_wayland.service; then
  fail "The stale Wayland compositor did not stop."
fi

printf '\nStale Plasma session stopped. SDDM will now restart.\n'
