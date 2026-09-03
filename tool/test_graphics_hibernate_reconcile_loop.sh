#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
LOOP="$SCRIPT_DIR/../packaging/nixos/legion-graphics-hibernate-reconcile-loop.sh"
command -v jq >/dev/null || {
  printf 'jq is required; run this test through nix shell nixpkgs#jq.\n' >&2
  exit 127
}
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

write_fake_cli() {
  local body=$1
  {
    printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail'
    printf '%s\n' "$body"
  } >"$TMP_DIR/legion_cli"
  chmod +x "$TMP_DIR/legion_cli"
}

run_loop() {
  bash "$LOOP" "$TMP_DIR/legion_cli" 0
}

assert_status() {
  local expected=$1
  shift
  set +e
  "$@" >"$TMP_DIR/stdout" 2>"$TMP_DIR/stderr"
  local actual=$?
  set -e
  if [[ $actual -ne $expected ]]; then
    printf 'Expected exit %d, got %d.\nstdout:\n' "$expected" "$actual" >&2
    cat "$TMP_DIR/stdout" >&2
    printf 'stderr:\n' >&2
    cat "$TMP_DIR/stderr" >&2
    exit 1
  fi
}

count_file="$TMP_DIR/count"
printf '0\n' >"$count_file"
export COUNT_FILE="$count_file"
# shellcheck disable=SC2016 # Written verbatim to the fake CLI.
write_fake_cli '
count=$(<"$COUNT_FILE")
printf "%d\n" "$((count + 1))" >"$COUNT_FILE"
if [[ $count -eq 0 ]]; then
  printf "%s\n" '\''{"schema_version":1,"effective_dgpu_state":"partial","expected_dgpu_state":"detached","reconciliation":"blocked","client_inspection_complete":false,"active_clients":[],"reconciliation_attempts":0}'\''
  exit 2
fi
if [[ $count -eq 1 ]]; then
  printf "%s\n" '\''{"schema_version":1,"effective_dgpu_state":"attached","expected_dgpu_state":"detached","reconciliation":"needed","client_inspection_complete":true,"active_clients":[],"reconciliation_attempts":0}'\''
  exit 2
fi
printf "%s\n" '\''{"schema_version":1,"effective_dgpu_state":"detached","expected_dgpu_state":"detached","reconciliation":"settled","client_inspection_complete":true,"active_clients":[],"reconciliation_attempts":1}'\''
'
assert_status 0 run_loop
[[ $(<"$count_file") == 3 ]]

printf '0\n' >"$count_file"
# shellcheck disable=SC2016 # Written verbatim to the fake CLI.
write_fake_cli '
count=$(<"$COUNT_FILE")
printf "%d\n" "$((count + 1))" >"$COUNT_FILE"
printf "%s\n" '\''{"schema_version":1,"effective_dgpu_state":"attached","expected_dgpu_state":"detached","reconciliation":"blocked","client_inspection_complete":true,"active_clients":[{"pid":4242}]}'\''
exit 2
'
assert_status 2 run_loop
[[ $(<"$count_file") == 1 ]]

write_fake_cli 'printf "%s\n" "not-json"; exit 2'
assert_status 1 run_loop

write_fake_cli 'printf "%s\n" '\''{"schema_version":1,"effective_dgpu_state":"attached","expected_dgpu_state":"attached","reconciliation":"settled","client_inspection_complete":true,"active_clients":[]}'\'''
assert_status 0 run_loop

write_fake_cli 'printf "%s\n" '\''{"schema_version":2,"effective_dgpu_state":"future","expected_dgpu_state":"future","reconciliation":"settled","client_inspection_complete":true,"active_clients":[]}'\'''
assert_status 1 run_loop

write_fake_cli 'printf "%s\n" '\''{"schema_version":1,"effective_dgpu_state":"partial","expected_dgpu_state":"detached","reconciliation":"blocked","client_inspection_complete":false,"active_clients":[]}'\''; exit 2'
assert_status 124 timeout 0.1s bash "$LOOP" "$TMP_DIR/legion_cli" 0.01

printf 'graphics hibernate reconciliation loop tests passed\n'
