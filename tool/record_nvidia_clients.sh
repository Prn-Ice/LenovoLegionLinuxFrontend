#!/usr/bin/env bash
# Save the processes holding NVIDIA device files open at the time of the check.
set -euo pipefail
umask 077

if [[ $# == 1 && $1 == --without-greeter ]]; then
  if [[ ! $(tty) =~ ^/dev/tty[0-9]+$ ]]; then
    echo 'Log out, press Ctrl+Alt+F3 at the sign-in screen, and run this from the text console.' >&2
    exit 1
  fi
  sessions=$(loginctl show-user "$UID" --property=Sessions --value)
  for session in $sessions; do
    type=$(loginctl show-session "$session" --property=Type --value)
    if [[ $type == wayland || $type == x11 ]]; then
      echo 'Your graphical session is still open. Log out before running this check.' >&2
      exit 1
    fi
  done
  greeter_state=$(systemctl show display-manager.service --property=ActiveState --value)
  if [[ $greeter_state != inactive ]]; then
    sudo -v
    restore_greeter() {
      if ! sudo systemctl start display-manager.service; then
        echo 'Could not restart the sign-in screen. Run sudo systemctl start display-manager.service to retry.' >&2
        exit 1
      fi
    }
    trap restore_greeter EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    trap 'exit 129' HUP
    sudo systemctl stop display-manager.service
  fi
elif (( $# )); then
  echo "Usage: $0 [--without-greeter]" >&2
  exit 2
fi

directory="$HOME/nvidia-clients"
mkdir -p -- "$directory"
report=$(mktemp --suffix=.txt "$directory/$(date +%Y%m%d-%H%M%S)-XXXXXX")
printf 'Report: %s\n' "$report"
printf 'Time: %s\nKernel: %s\n' "$(date --iso-8601=seconds)" "$(uname -r)" >"$report"
if [[ ${1:-} == --without-greeter ]]; then
  systemctl show display-manager.service --property=ActiveState >>"$report"
fi

devices=()
for node in /dev/nvidia[0-9]* /dev/nvidia-modeset; do
  if [[ -c "$node" ]]; then devices+=("$node"); fi
done
for entry in /sys/class/drm/card[0-9]* /sys/class/drm/renderD[0-9]*; do
  node="/dev/dri/${entry##*/}"
  if [[ -c "$node" && -r "$entry/device/vendor" && $(<"$entry/device/vendor") == 0x10de ]]; then
    devices+=("$node")
  fi
done
if ((${#devices[@]} == 0)); then
  echo 'No NVIDIA device nodes found.' | tee -a "$report"
  exit 0
fi
printf 'Checking %s\n' "${devices[@]}" >>"$report"
if ! lsof_bin=$(type -P lsof); then
  echo 'Could not check processes. Install lsof and run the script again.' | tee -a "$report" >&2
  exit 1
fi
command=("$(realpath -- "$lsof_bin")" -nP -Q -f -- "${devices[@]}")
if ((EUID != 0)); then command=(sudo -- "${command[@]}"); fi
if result=$("${command[@]}" 2>>"$report"); then
  printf '%s\n' "${result:-No processes reported on the checked devices.}" | tee -a "$report"
else
  echo 'Process check failed. See the report for details.' | tee -a "$report" >&2
  exit 1
fi
