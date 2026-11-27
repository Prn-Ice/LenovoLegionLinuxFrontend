#!/usr/bin/env bash
set -euo pipefail

CLI="/run/current-system/sw/bin/legion_cli"
STARTED_AT=$(date --iso-8601=seconds)
LOG="/tmp/lllf-restore-hybrid-${STARTED_AT//:/-}.log"
display_manager_stopped=0
transition_requested=0

exec > >(tee -a "$LOG") 2>&1

restart_user_audio() {
  systemctl --user start \
    pipewire.socket pipewire-pulse.socket \
    pipewire.service wireplumber.service pipewire-pulse.service
}

# shellcheck disable=SC2329 # Invoked by the EXIT trap.
cleanup() {
  local status=$?
  trap - EXIT
  if [[ "$display_manager_stopped" -eq 1 && "$transition_requested" -eq 0 ]]; then
    printf '\nRestarting the display manager after an interrupted preflight.\n' >&2
    restart_user_audio || true
    sudo systemctl start display-manager.service || true
  elif [[ "$display_manager_stopped" -eq 1 ]]; then
    printf '\nHybrid was not confirmed. Keep the display manager stopped; reboot or restore Hybrid in BIOS.\n' >&2
  fi
  exit "$status"
}
trap cleanup EXIT

tty_path=$(tty 2>/dev/null || true)
case "$tty_path" in
  /dev/tty[0-9]*) ;;
  *)
    printf 'ERROR: Run this script from a Linux virtual console such as Ctrl+Alt+F3, not %s.\n' "$tty_path" >&2
    exit 1
    ;;
esac

if [[ ! -x "$CLI" ]]; then
  printf 'ERROR: Validated CLI is unavailable at %s.\n' "$CLI" >&2
  exit 1
fi

printf 'Restoring Hybrid policy at %s\n' "$STARTED_AT"
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

set +e
transition_requested=1
sudo "$CLI" --donotexpecthwmon graphics-mode set hybrid --json
result=$?
set -e

printf '\nCurrent selected policy:\n'
$CLI --donotexpecthwmon graphics-mode status || true
printf '\nRelevant kernel messages:\n'
journalctl -k -b --since "$STARTED_AT" --no-pager \
  | grep -Ei 'nvidia|drm|pcie|pci|acpi|legion|snd_hda' || true

if [[ "$result" -eq 0 ]]; then
  if systemctl cat nvidia-container-toolkit-cdi-generator.service >/dev/null 2>&1; then
    printf '\nRegenerating NVIDIA container CDI state.\n'
    if ! sudo systemctl restart nvidia-container-toolkit-cdi-generator.service; then
      printf 'WARNING: NVIDIA CDI regeneration failed; desktop recovery can continue.\n' >&2
    fi
  fi
  printf '\nHybrid topology is settled. Starting the display manager.\n'
  transition_requested=0
  restart_user_audio
  sudo systemctl start display-manager.service
  display_manager_stopped=0
else
  printf '\nHybrid was not confirmed. Keep the graphical session stopped.\n' >&2
  printf 'Run sudo reboot; if Linux does not recover, restore Hybrid/Switchable graphics in BIOS.\n' >&2
fi

printf 'Command exit: %d\nLog: %s\n' "$result" "$LOG"
exit "$result"
