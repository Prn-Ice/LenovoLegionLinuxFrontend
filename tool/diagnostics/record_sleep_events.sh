#!/usr/bin/env bash
# Save journal events without requesting sleep or changing settings.
set -euo pipefail
umask 077

if (($#)); then
  echo 'Usage: bash tool/diagnostics/record_sleep_events.sh' >&2
  exit 2
fi
root=${XDG_STATE_HOME:-$HOME/.local/state}
directory=$(mktemp -d "$root/legion-sleep-recorder/$(date +%Y%m%d-%H%M%S)-XXXXXXXX" 2>/dev/null) || {
  mkdir -p "$root/legion-sleep-recorder"
  directory=$(mktemp -d "$root/legion-sleep-recorder/$(date +%Y%m%d-%H%M%S)-XXXXXXXX")
}
count=0
journal_pid=''
max_bytes=$((8 * 1024 * 1024))
# shellcheck source=tool/diagnostics/sleep_event_storage.sh
source "$(dirname "${BASH_SOURCE[0]}")/sleep_event_storage.sh"

finish() {
  local status=$?
  trap - EXIT INT TERM HUP
  if [[ -n "$journal_pid" ]]; then
    kill -TERM "$journal_pid" 2>/dev/null || true
    # Bound shutdown even if the journal command ignores SIGTERM.
    for ((attempt=0; attempt<50; attempt++)); do
      kill -0 "$journal_pid" 2>/dev/null || break
      sleep 0.1
    done
    kill -KILL "$journal_pid" 2>/dev/null || true
    wait "$journal_pid" 2>/dev/null || true
  fi
  append_event "$directory" "$max_bytes" "$(jq -cn --arg time "$(date --iso-8601=ns)" --argjson count "$count" \
    '{recorder_stopped:$time,saved_events:$count}')" || status=1
  rm -f "$directory/journal.fifo"
  printf 'Logs retained: %s\n' "$directory"
  exit "$status"
}
trap finish EXIT
trap 'echo "Stopping recorder."; exit 0' INT TERM HUP

append_event "$directory" "$max_bytes" "$(jq -cn --arg time "$(date --iso-8601=ns)" \
  --arg boot "$(cat /proc/sys/kernel/random/boot_id)" \
  --arg generation "$(readlink -f /run/current-system || true)" \
  '{recorder_started:$time,boot_id:$boot,generation:$generation,
    limitation:"User recorder freezes during sleep; no physical power-off proof"}')"
printf 'Saving sleep/display events to %s\n' "$directory"
echo 'Leave this terminal open. Ctrl+C stops recording. No sleep or settings changes requested.'
echo 'Up to four 8 MiB files are kept for this run. Logs may contain process/device details.'
mkfifo "$directory/journal.fifo"
journalctl --boot --since=-30min --follow --output=json --no-pager \
  _TRANSPORT=kernel \
  + _SYSTEMD_UNIT=systemd-suspend.service \
  + _SYSTEMD_UNIT=systemd-hibernate.service \
  + _SYSTEMD_UNIT=systemd-suspend-then-hibernate.service \
  + _SYSTEMD_UNIT=systemd-logind.service \
  + _SYSTEMD_UNIT=legion-graphics-reconcile.service \
  + SYSLOG_IDENTIFIER=org_kde_powerdevil + _COMM=kwin_wayland >"$directory/journal.fifo" &
journal_pid=$!
while IFS= read -r line || [[ -n "$line" ]]; do
  event=$(printf '%s\n' "$line" | jq -c 'select(type == "object")') || {
    echo 'Recorder failed: Invalid journal event' >&2
    exit 1
  }
  [[ -n "$event" ]] || { echo 'Invalid journal event' >&2; exit 1; }
  if printf '%s\n' "$event" | keep_event; then
    append_event "$directory" "$max_bytes" "$event"
    count=$((count + 1))
    if ((count == 1)); then echo 'Journal events are being saved.'; fi
  fi
done <"$directory/journal.fifo"
status=0
wait "$journal_pid" || status=$?
journal_pid=''
if ((status)); then
  echo "Recorder failed: journalctl stopped with exit $status; check journal permissions" >&2
  exit 1
elif ((count == 0)); then
  echo 'Recorder failed: No journal events received; access or capture is unverified' >&2
  exit 1
fi
