#!/usr/bin/env bash
# Retrieve guest evidence before the caller deletes its disposable VM.

retrieve_distro_evidence() {
  local output=$1 archive=$2 qualification_status=$3 port=$4
  shift 4
  local journal_status=0 archive_status=0
  timeout 60 ssh "$@" -p "$port" root@127.0.0.1 \
    'journalctl -b --no-pager' > "$output/journal.log" 2>&1 || journal_status=$?
  timeout 180 scp "$@" -P "$port" "root@127.0.0.1:/root/$archive" "$output/" \
    > "$output/evidence-transfer.log" 2>&1 || archive_status=$?
  printf 'qualification=%s\njournal=%s\narchive=%s\n' \
    "$qualification_status" "$journal_status" "$archive_status" \
    > "$output/qualification-status.txt"
  if (( qualification_status != 0 )); then return "$qualification_status"; fi
  return "$archive_status"
}
