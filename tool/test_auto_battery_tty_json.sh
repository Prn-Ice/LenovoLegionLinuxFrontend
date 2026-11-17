#!/usr/bin/env bash
# Test only the hardware script's JSON predicates, never its executable body.
set -euo pipefail
source=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/test_auto_battery_tty.sh
root=$(mktemp -d -t legion-auto-json-test-XXXXXX)
trap 'rm -rf -- "$root"' EXIT
awk '
  /^json_matches\(\) \{|^clients_clear\(\) \{/ { copying=1 }
  copying { print }
  copying && /^}/ { copying=0; count++ }
  END { if (count != 2) exit 1 }
' "$source" > "$root/predicates.sh"
# shellcheck source=/dev/null
source "$root/predicates.sh"
status='{"selected_mode":"hybrid-auto","expected_dgpu_state":"attached","effective_dgpu_state":"attached","reconciliation":"settled","client_inspection_complete":true,"active_clients":[]}'
json_matches hybrid-auto attached attached settled <<< "$status"
clients_clear <<< "$status"
for change in '.selected_mode="hybrid"' '.expected_dgpu_state="detached"' '.effective_dgpu_state="detached"' '.reconciliation="needed"'; do
  changed=$(jq "$change" <<< "$status")
  if json_matches hybrid-auto attached attached settled <<< "$changed"; then
    printf 'Unexpected topology match: %s\n' "$change" >&2; exit 1
  fi
done
for change in '.client_inspection_complete=false' '.client_inspection_complete=1' '.active_clients=[{pid:42}]' '.active_clients=null' 'del(.active_clients)'; do
  changed=$(jq "$change" <<< "$status")
  if clients_clear <<< "$changed"; then
    printf 'Unexpected clear clients: %s\n' "$change" >&2; exit 1
  fi
done
for invalid in '' 'not-json' 'null' '[]' "$status $status"; do
  if json_matches hybrid-auto attached attached settled <<< "$invalid" 2> /dev/null; then
    printf 'Unexpected topology match for invalid JSON\n' >&2; exit 1
  fi
  if clients_clear <<< "$invalid" 2> /dev/null; then
    printf 'Unexpected clear clients for invalid JSON\n' >&2; exit 1
  fi
done
printf 'PASS: Auto topology and client JSON predicates reject unsafe or malformed status\n'
