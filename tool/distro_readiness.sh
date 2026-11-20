#!/usr/bin/env bash

is_ssh_transport_failure() {
  grep -Eq '^(kex_exchange_identification: read: Connection reset by peer|kex_exchange_identification: Connection closed by remote host|ssh_exchange_identification: read: Connection reset by peer|ssh_exchange_identification: Connection closed by remote host|Connection reset by [^[:space:]]+( port [0-9]+)?|Connection closed by [^[:space:]]+( port [0-9]+)?|client_loop: send disconnect: Broken pipe|ssh: connect to host [^[:space:]]+ port [0-9]+: (Connection refused|Connection timed out|No route to host))$'
}

# Wait for cloud-init after SSH first becomes reachable. Cloud-init status is
# read-only, so a known SSH transport failure can safely retry within one
# deadline. Every other remote status stops qualification immediately.
wait_for_cloud_init() {
  local wait_seconds="$1"
  shift
  local ssh_command=("$@")
  local deadline=$((SECONDS + wait_seconds))

  while true; do
    local output result remaining
    remaining=$((deadline - SECONDS))
    if ((remaining <= 0)); then
      echo 'Cloud-init readiness deadline expired.' >&2
      return 124
    fi

    if output="$(timeout --foreground --signal=KILL "$remaining" \
      "${ssh_command[@]}" \
      "timeout $remaining cloud-init status --wait" 2>&1)"; then
      result=0
    else
      result=$?
    fi
    # GNU timeout returns 137 after KILL. Report an exhausted local deadline
    # with timeout's standard status 124.
    if ((result == 137 && SECONDS >= deadline)); then
      result=124
    fi

    if [[ -n $output ]]; then
      if ((result == 0)); then
        printf '%s\n' "$output"
      else
        printf '%s\n' "$output" >&2
      fi
    fi

    if ((result != 255)) || ! is_ssh_transport_failure <<<"$output"; then
      if ((result == 124)); then
        echo 'Timed out while waiting for cloud-init readiness.' >&2
      fi
      return "$result"
    fi

    echo 'SSH transport reset while waiting for cloud-init; retrying.' >&2
    sleep 1
  done
}
