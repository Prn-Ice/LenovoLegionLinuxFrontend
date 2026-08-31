#!/usr/bin/env bash
set -euo pipefail

CLI="/run/current-system/sw/bin/legion_cli"
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
STARTED_AT=$(date --iso-8601=seconds)
LOG="/tmp/lllf-auto-ac-${STARTED_AT//:/-}.log"
display_manager_stopped=0
transition_requested=0

exec > >(tee -a "$LOG") 2>&1

# shellcheck disable=SC2329 # Invoked by the EXIT trap.
cleanup() {
  local status=$?
  trap - EXIT
  if [[ "$display_manager_stopped" -eq 1 && "$transition_requested" -eq 0 ]]; then
    printf '\nRestarting the display manager after an interrupted preflight.\n' >&2
    sudo systemctl start display-manager.service || true
  elif [[ "$display_manager_stopped" -eq 1 ]]; then
    printf '\nGraphics state is uncertain; keep the display manager stopped and run:\n  %s/restore_hybrid_tty.sh\n' "$SCRIPT_DIR" >&2
  fi
  exit "$status"
}
trap cleanup EXIT

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  printf 'No firmware write was requested. Log: %s\n' "$LOG" >&2
  exit 1
}

tty_path=$(tty 2>/dev/null || true)
case "$tty_path" in
  /dev/tty[0-9]*) ;;
  *) fail "Run this script from a Linux virtual console such as Ctrl+Alt+F3, not $tty_path." ;;
esac

[[ -x "$CLI" ]] || fail "Validated CLI is unavailable at $CLI."

current_mode=$("$CLI" --donotexpecthwmon graphics-mode status)
[[ "$current_mode" == "hybrid" ]] || fail "Expected Hybrid before testing, but selected mode is $current_mode."

ac_online=0
external_supply_seen=0
for type_path in /sys/class/power_supply/*/type; do
  [[ -r "$type_path" ]] || continue
  read -r supply_type < "$type_path"
  case "$supply_type" in
    Mains|USB|USB_C|USB_CDP|USB_DCP|USB_PD|USB_PD_DRP|Wireless) ;;
    *) continue ;;
  esac

  external_supply_seen=1
  online_path="${type_path%/type}/online"
  [[ -r "$online_path" ]] || fail "Cannot inspect external power at $online_path."
  read -r online < "$online_path"
  case "$online" in
    0) ;;
    1) ac_online=1 ;;
    *) fail "External power at $online_path returned invalid state $online." ;;
  esac
done
[[ "$external_supply_seen" -eq 1 ]] || fail "No readable external power supply was found."
[[ "$ac_online" -eq 1 ]] || fail "Hybrid Auto AC testing requires the power adapter to remain connected."

for status_path in /sys/class/drm/card[0-9]-*/status; do
  [[ -r "$status_path" ]] || continue
  read -r connector_status < "$status_path"
  connector=${status_path%/status}
  connector=${connector##*/}
  if [[ "$connector_status" == "connected" && "$connector" != *-eDP-* ]]; then
    fail "External connector $connector is active. Disconnect every external display first."
  fi
done

printf 'Starting guarded Hybrid -> Hybrid Auto test on AC at %s\n' "$STARTED_AT"
printf 'Evidence log: %s\n' "$LOG"
sudo -v

sudo systemctl stop display-manager.service
display_manager_stopped=1
systemctl --user stop graphical-session.target

while read -r session_id _; do
  session_type=$(loginctl show-session "$session_id" --property=Type --value 2>/dev/null || true)
  if [[ "$session_type" == "wayland" || "$session_type" == "x11" ]]; then
    sudo loginctl terminate-session "$session_id"
  fi
done < <(loginctl list-sessions --no-legend)

pkill -TERM -x code 2>/dev/null || true
sleep 5

printf '\nRoot-observed graphics state before the write:\n'
sudo "$CLI" --donotexpecthwmon graphics-mode status --json

set +e
transition_requested=1
sudo "$CLI" --donotexpecthwmon graphics-mode set hybrid-auto --json
result=$?
set -e

printf '\nPost-command selected policy:\n'
"$CLI" --donotexpecthwmon graphics-mode status || true
printf '\nPower-supply state:\n'
for online_path in /sys/class/power_supply/*/online; do
  [[ -r "$online_path" ]] || continue
  printf '%s=' "${online_path%/online}"
  printf '%s\n' "$(< "$online_path")"
done
printf '\nRelevant kernel messages:\n'
journalctl -k -b --since "$STARTED_AT" --no-pager \
  | grep -Ei 'nvidia|drm|pcie|pci|acpi|legion|snd_hda|power_supply' || true

case "$result" in
  0)
    printf '\nThe backend confirmed attached, settled Hybrid Auto topology on AC.\n'
    printf 'Keep AC connected. Starting the display manager.\n'
    transition_requested=0
    sudo systemctl start display-manager.service
    display_manager_stopped=0
    ;;
  2)
    printf '\nThe backend blocked the transition before changing firmware.\n'
    transition_requested=0
    sudo systemctl start display-manager.service
    display_manager_stopped=0
    ;;
  *)
    printf '\nHybrid Auto was not confirmed. Keep the graphical session stopped.\n' >&2
    printf 'Restore Hybrid with:\n  %s/restore_hybrid_tty.sh\n' "$SCRIPT_DIR" >&2
    ;;
esac

printf 'Command exit: %d\nLog: %s\n' "$result" "$LOG"
exit "$result"
