#!/usr/bin/env bash
# Capture a stopped-desktop preflight, without changing graphics or sleeping.
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
  printf 'Run with bash as your normal user, not with sudo.\n' >&2
  exit 1
fi
console=$(tty 2>/dev/null || true)
if [[ ! $console =~ ^/dev/tty[0-9]+$ ]]; then
  printf 'Log out of Plasma, press Ctrl+Alt+F3, log in, then run this script.\n' >&2
  exit 1
fi

CLI=/run/current-system/sw/bin/legion_cli
[[ -x $CLI ]] || { printf 'legion_cli is unavailable.\n' >&2; exit 1; }
umask 077
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/legion-graphics-check"
mkdir -p "$LOG_DIR"
LOG=$(mktemp "$LOG_DIR/check-$(date +%Y%m%d-%H%M%S)-XXXXXX.log")
exec > >(tee -a "$LOG") 2>&1
restore_display=0
restore_audio=0
audio_units=()

# shellcheck disable=SC2329 # Invoked by the EXIT trap.
cleanup() {
  local result=$?
  trap - EXIT
  if [[ $restore_audio -eq 1 ]]; then
    printf '\nRestoring previously active user audio units.\n'
    if ! systemctl --user start "${audio_units[@]}"; then
      printf 'Audio recovery failed. Run: systemctl --user start' >&2
      printf ' %q' "${audio_units[@]}" >&2
      printf '\n' >&2
      result=1
    fi
  fi
  if [[ $restore_display -eq 1 ]]; then
    printf '\nRestoring the graphical login screen.\n'
    if ! sudo systemctl start display-manager.service; then
      printf 'Recovery failed. Run: sudo systemctl start display-manager.service\n' >&2
      result=1
    fi
  fi
  printf '\nLog saved: %s\n' "$LOG"
  printf 'No graphics mode change or sleep was requested.\n'
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

printf 'Graphics check: %s\nConsole: %s\nLog: %s\n' "$(date --iso-8601=seconds)" "$console" "$LOG"
printf 'This briefly stops the login screen and user audio, records status, then restores them.\n'
printf 'Your Plasma session should already be logged out. Continue? [y/N] '
read -r answer
[[ $answer == y || $answer == Y ]] || exit 0
sudo -v

printf '\nBoot ID:\n'
cat /proc/sys/kernel/random/boot_id
printf '\nEffective sleep configuration:\n'
systemd-analyze cat-config systemd/sleep.conf
printf '\nLoaded sleep guard:\n'
systemctl show systemd-suspend-then-hibernate.service \
  -p LoadState -p ExecStart -p Requires -p After

display_state=$(systemctl is-active display-manager.service || true)
case "$display_state" in
  active)
    # Set before stopping so an interrupted stop also attempts recovery.
    restore_display=1
    sudo systemctl stop display-manager.service
    ;;
  inactive) ;;
  *) printf 'Unexpected display manager state: %s; stopping check.\n' "$display_state" >&2; exit 1 ;;
esac
printf '\nRecording user audio state before pausing it:\n'
for unit in pipewire.socket pipewire-pulse.socket pipewire.service wireplumber.service pipewire-pulse.service; do
  audio_state=$(systemctl --user show "$unit" --property=ActiveState --value)
  printf '%s: %s\n' "$unit" "$audio_state"
  case "$audio_state" in
    active) audio_units+=("$unit") ;;
    inactive|failed) ;;
    *) printf 'Unexpected audio state; stopping check without pausing audio.\n' >&2; exit 1 ;;
  esac
done
if [[ ${#audio_units[@]} -gt 0 ]]; then
  # Stop sockets and services together to avoid immediate socket reactivation.
  restore_audio=1
  systemctl --user stop "${audio_units[@]}"
fi
sleep 3
printf '\nAuthoritative graphics status with display manager and user audio stopped:\n'
sudo "$CLI" --donotexpecthwmon graphics-mode status --json
printf '\nFailed services:\n'
systemctl --failed --no-pager
printf '\nCapture complete. Return to the desktop and tell the agent the check finished.\n'
