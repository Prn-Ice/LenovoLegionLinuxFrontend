#!/usr/bin/env bash
# Save the processes holding NVIDIA device files open at the time of the check.
set -euo pipefail
umask 077

directory="$HOME/nvidia-clients"
mkdir -p -- "$directory"
report=$(mktemp --suffix=.txt "$directory/$(date +%Y%m%d-%H%M%S)-XXXXXX")
printf 'Report: %s\n' "$report"
printf 'Time: %s\nKernel: %s\n' "$(date --iso-8601=seconds)" "$(uname -r)" >"$report"

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
