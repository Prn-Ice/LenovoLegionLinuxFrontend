# shellcheck shell=bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  printf 'Usage: %s LEGION_CLI RETRY_DELAY_SECONDS\n' "$0" >&2
  exit 64
fi

cli=$1
retry_delay_seconds=$2

while true; do
  set +e
  graphics_state=$(
    "$cli" --donotexpecthwmon graphics-mode reconcile --json
  )
  cli_status=$?
  set -e

  printf '%s\n' "$graphics_state"
  if ! outcome=$(jq --exit-status --raw-output '
    . as $status |
    if type != "object"
      or .schema_version != 1
      or (["settled", "blocked", "needed", "unknown"] | index($status.reconciliation)) == null
      or (["attached", "detached", "partial", "unknown"] | index($status.effective_dgpu_state)) == null
      or (["attached", "detached"] | index($status.expected_dgpu_state)) == null
      or (.client_inspection_complete | type) != "boolean"
      or (.active_clients | type) != "array"
    then error("invalid graphics reconciliation response")
    elif (.active_clients | length) > 0 then "clients"
    elif .reconciliation == "settled"
      and .client_inspection_complete
      and .effective_dgpu_state == .expected_dgpu_state
    then "settled"
    else "retry"
    end
  ' <<<"$graphics_state"); then
    printf 'Graphics reconciliation returned an invalid response (CLI exit %d).\n' \
      "$cli_status" >&2
    exit 1
  fi

  case "$outcome" in
    clients)
      printf 'Graphics reconciliation stopped because dGPU clients are active.\n' >&2
      exit 2
      ;;
    settled)
      if [[ $cli_status -ne 0 ]]; then
        printf 'Graphics reconciliation reported settled state with CLI exit %d.\n' \
          "$cli_status" >&2
        exit 1
      fi
      exit 0
      ;;
    retry)
      printf 'Graphics topology is not ready (CLI exit %d); retrying in %s seconds.\n' \
        "$cli_status" "$retry_delay_seconds" >&2
      sleep "$retry_delay_seconds"
      ;;
    *)
      printf 'Graphics reconciliation produced an unknown outcome.\n' >&2
      exit 1
      ;;
  esac
done
