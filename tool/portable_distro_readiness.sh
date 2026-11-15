#!/usr/bin/env bash

# Wait for cloud-init after SSH becomes reachable. Only retry a known SSH
# transport failure; a cloud-init or remote-command failure must stop the VM
# qualification.
wait_for_cloud_init() {
  local wait_seconds="$1"
  shift
  local ssh_command=("$@")
  local deadline=$((SECONDS + wait_seconds))

  while true; do
    local output result remaining remote_timeout marker_status
    remaining=$((deadline - SECONDS))
    if (( remaining <= 0 )); then
      printf 'Readiness deadline expired before cloud-init completed\n' >&2
      return 124
    fi
    # Both timeouts use the same remaining budget. The outer timeout bounds a
    # stalled transport and never extends the total budget.
    remote_timeout="$remaining"
    if output="$(timeout --foreground "$remaining" \
      "${ssh_command[@]}" \
      "timeout $remote_timeout sh -c 'cloud-init status --wait; status=\$?; printf __LLLF_CLOUD_INIT_STATUS__%s\\n \"\$status\"; exit \"\$status\"'" 2>&1)"; then
      result=0
    else
      result=$?
    fi

    if [[ "$output" =~ __LLLF_CLOUD_INIT_STATUS__([0-9]+) ]]; then
      marker_status="${BASH_REMATCH[1]}"
      output="${output//__LLLF_CLOUD_INIT_STATUS__$marker_status/}"
      if [[ -n "$output" ]]; then
        if (( marker_status == 0 )); then
          printf '%s\n' "$output"
        else
          printf '%s\n' "$output" >&2
        fi
      fi
      return "$marker_status"
    fi
    if [[ -n "$output" ]]; then
      printf '%s\n' "$output" >&2
    fi

    # SSH uses 255 for transport errors. Require an actual SSH diagnostic too,
    # so arbitrary remote output can never make a command retryable.
    if (( result != 124 && result != 255 )) || \
      { (( result == 255 )) && ! grep -Eiq \
        '(^|[[:space:]])(kex_exchange_identification:|ssh: connect to host [^:]+ port [0-9]+: Connection (refused|timed out)|Connection (reset|closed) by |client_loop: send disconnect: Broken pipe)' \
        <<<"$output"; }; then
      return "$result"
    fi
    if (( SECONDS >= deadline )); then
      printf 'SSH transport did not remain available while waiting for cloud-init\n' >&2
      return 255
    fi
    printf 'Transient SSH transport failure while waiting for cloud-init; retrying\n' >&2
    sleep 1
  done
}
