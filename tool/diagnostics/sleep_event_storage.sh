#!/usr/bin/env bash
# Storage and filtering for the journal recorder. The caller owns its directory.
append_event() {
  local directory=$1 max_bytes=$2 data=$3 size current source target index
  size=$(LC_ALL=C printf '%s\n' "$data" | wc -c) || return 1
  if ((size > max_bytes)); then
    echo 'Journal event exceeds the file size limit' >&2
    return 1
  fi
  if [[ -e "$directory/events.jsonl" ]]; then
    current=$(stat -c %s "$directory/events.jsonl") || return 1
    if ((current + size > max_bytes)); then
      for ((index=3; index>=1; index--)); do
        source="$directory/events.$((index - 1)).jsonl"
        [[ $index != 1 ]] || source="$directory/events.jsonl"
        target="$directory/events.$index.jsonl"
        if [[ -e "$source" ]]; then mv -f -- "$source" "$target" || return 1; fi
      done
    fi
  fi
  printf '%s\n' "$data" >>"$directory/events.jsonl" || return 1
  # GNU sync -f persists file data and directory updates on this filesystem.
  sync -f "$directory/events.jsonl"
}

keep_event() {
  # Retain PowerDevil sleep and failure messages, not routine display-bus polls.
  jq -e '
    .SYSLOG_IDENTIFIER != "org_kde_powerdevil" or
    ((.MESSAGE // "" | tostring) | test("sleep|suspend|hibernat|error|fail|outputs|button|lid|idle|battery|critical"; "i"))
    ' >/dev/null
}
