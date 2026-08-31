#!/usr/bin/env bash
set -euo pipefail

CLI="/run/current-system/sw/bin/legion_cli"
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
STARTED_AT=$(date --iso-8601=seconds)
LOG="/tmp/lllf-auto-battery-${STARTED_AT//:/-}.log"
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
    printf '\nGraphics state is uncertain; keep the display manager stopped, reconnect AC, then run:\n  %s/restore_hybrid_tty.sh\n' "$SCRIPT_DIR" >&2
  fi
  exit "$status"
}
trap cleanup EXIT

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  printf 'No power transition was requested. Log: %s\n' "$LOG" >&2
  exit 1
}

power_state() {
  local external_supply_seen=0
  local online_seen=0
  local online_path online supply_type type_path

  for type_path in /sys/class/power_supply/*/type; do
    [[ -r "$type_path" ]] || continue
    read -r supply_type < "$type_path" || {
      printf 'unknown\n'
      return
    }
    case "$supply_type" in
      Mains|USB|USB_C|USB_CDP|USB_DCP|USB_PD|USB_PD_DRP|Wireless) ;;
      *) continue ;;
    esac

    external_supply_seen=1
    online_path="${type_path%/type}/online"
    [[ -r "$online_path" ]] || {
      printf 'unknown\n'
      return
    }
    read -r online < "$online_path" || {
      printf 'unknown\n'
      return
    }
    case "$online" in
      0) ;;
      1) online_seen=1 ;;
      *)
        printf 'unknown\n'
        return
        ;;
    esac
  done

  if [[ "$external_supply_seen" -eq 0 ]]; then
    printf 'unknown\n'
  elif [[ "$online_seen" -eq 1 ]]; then
    printf 'ac\n'
  else
    printf 'battery\n'
  fi
}

json_matches() {
  local selected=$1
  local expected=$2
  local effective=$3
  local reconciliation=$4

  python3 -c '
import json
import sys

status = json.load(sys.stdin)
matches = (
    status["selected_mode"] == sys.argv[1]
    and status["expected_dgpu_state"] == sys.argv[2]
    and status["effective_dgpu_state"] == sys.argv[3]
    and status["reconciliation"] == sys.argv[4]
)
raise SystemExit(0 if matches else 1)
' "$selected" "$expected" "$effective" "$reconciliation"
}

clients_clear() {
  python3 -c '
import json
import sys

status = json.load(sys.stdin)
clear = status["client_inspection_complete"] and not status["active_clients"]
raise SystemExit(0 if clear else 1)
'
}

tty_path=$(tty 2>/dev/null || true)
case "$tty_path" in
  /dev/tty[0-9]*) ;;
  *) fail "Run this script from a Linux virtual console such as Ctrl+Alt+F3, not $tty_path." ;;
esac

[[ -x "$CLI" ]] || fail "Validated CLI is unavailable at $CLI."

current_mode=$("$CLI" --donotexpecthwmon graphics-mode status)
[[ "$current_mode" == "hybrid-auto" ]] || fail "Expected Hybrid Auto before testing, but selected mode is $current_mode."
[[ "$(power_state)" == "ac" ]] || fail "Start with the power adapter connected."

for status_path in /sys/class/drm/card[0-9]-*/status; do
  [[ -r "$status_path" ]] || continue
  read -r connector_status < "$status_path"
  connector=${status_path%/status}
  connector=${connector##*/}
  if [[ "$connector_status" == "connected" && "$connector" != *-eDP-* ]]; then
    fail "External connector $connector is active. Disconnect every external display first."
  fi
done

printf 'Starting guarded Hybrid Auto AC -> battery test at %s\n' "$STARTED_AT"
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

printf '\nRoot-observed graphics state before unplugging AC:\n'
before_status=$(sudo "$CLI" --donotexpecthwmon graphics-mode status --json)
printf '%s\n' "$before_status"

if ! json_matches hybrid-auto attached attached settled <<< "$before_status" \
  || ! clients_clear <<< "$before_status"; then
  printf '\nHybrid Auto is not safely settled on AC with zero dGPU clients.\n' >&2
  printf 'Starting the display manager without requesting a power transition.\n' >&2
  sudo systemctl start display-manager.service
  display_manager_stopped=0
  exit 2
fi

transition_requested=1
printf '\nUnplug the power adapter now. Waiting up to 90 seconds for battery power...\n'
state=ac
for _ in {1..90}; do
  state=$(power_state)
  [[ "$state" == "ac" ]] || break
  sleep 1
done

if [[ "$state" != "battery" ]]; then
  printf 'Battery power was not confirmed; observed power state: %s.\n' "$state" >&2
  if [[ "$state" == "ac" ]]; then
    printf 'Starting the display manager because AC is still connected.\n' >&2
    transition_requested=0
    sudo systemctl start display-manager.service
    display_manager_stopped=0
  else
    printf 'Keep the graphical session stopped, reconnect AC, then run:\n  %s/restore_hybrid_tty.sh\n' "$SCRIPT_DIR" >&2
  fi
  exit 1
fi

printf 'Battery power detected. Observing native Auto behavior for 30 seconds.\n'
automatic=0
for attempt in {0..30}; do
  observed_status=$(sudo "$CLI" --donotexpecthwmon graphics-mode status --json)
  printf 'Auto observation %d: %s\n' "$attempt" "$observed_status"
  if json_matches hybrid-auto detached detached settled <<< "$observed_status"; then
    automatic=1
    break
  fi
  sleep 1
done

result=0
if [[ "$automatic" -eq 0 ]]; then
  printf '\nNative Auto did not settle within 30 seconds; invoking backend reconciliation.\n'
  set +e
  sudo "$CLI" --donotexpecthwmon graphics-mode reconcile --json
  result=$?
  set -e
fi

printf '\nFinal root-observed graphics state:\n'
final_status=$(sudo "$CLI" --donotexpecthwmon graphics-mode status --json)
printf '%s\n' "$final_status"
if ! json_matches hybrid-auto detached detached settled <<< "$final_status"; then
  result=3
fi

printf '\nRelevant kernel messages:\n'
journalctl -k -b --since "$STARTED_AT" --no-pager \
  | grep -Ei 'nvidia|drm|pcie|pci|acpi|legion|snd_hda|power_supply' || true

if [[ "$result" -eq 0 ]]; then
  if [[ "$automatic" -eq 1 ]]; then
    printf '\nFirmware Auto detached the dGPU without explicit reconciliation.\n'
  else
    printf '\nBackend reconciliation detached the dGPU after the AC power event.\n'
  fi
  printf 'Keep AC disconnected. Starting the display manager on AMD graphics.\n'
  transition_requested=0
  sudo systemctl start display-manager.service
  display_manager_stopped=0
else
  printf '\nDetached Hybrid Auto topology was not confirmed.\n' >&2
  printf 'Keep the graphical session stopped, reconnect AC, then run:\n  %s/restore_hybrid_tty.sh\n' "$SCRIPT_DIR" >&2
fi

printf 'Command exit: %d\nLog: %s\n' "$result" "$LOG"
exit "$result"
