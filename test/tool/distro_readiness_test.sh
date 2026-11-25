#!/usr/bin/env bash
# Exercise cloud-init readiness with local SSH and cloud-init fakes.
# shellcheck disable=SC2016
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck source=control/test/helper_session_test.sh
source "$root/control/test/helper_session_test.sh"
setup() {
  cp "$root/tool/distro_readiness.sh" "$fixture/helper with spaces.sh"
  export FAKE_SSH_CALLS="$fixture/ssh calls" FAKE_CLOUD_INIT_CALLS="$fixture/cloud init calls" \
    FAKE_TRANSPORT_STATE="$fixture/transport state"
  cat >"$fixture/fake ssh" <<'EOF'
#!/usr/bin/env bash
set -eu
printf '%s\0' "$@" >> "$FAKE_SSH_CALLS"
printf '\n' >> "$FAKE_SSH_CALLS"
case "$FAKE_SSH_MODE" in
  reset-once)
    if [[ ! -e $FAKE_TRANSPORT_STATE ]]; then
      touch "$FAKE_TRANSPORT_STATE"
      echo 'kex_exchange_identification: read: Connection reset by peer' >&2
      exit 255
    fi
    ;;
  hang)
    trap '' TERM
    while true; do read -r -t 1 || true; done
    ;;
esac
remote_command="${!#}"
exec bash -c "$remote_command"
EOF
  cat >"$fixture/cloud-init" <<'EOF'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> "$FAKE_CLOUD_INIT_CALLS"
case "$FAKE_CLOUD_INIT_MODE" in
  success) echo 'status: done' ;;
  critical) echo 'status: error' >&2; exit 1 ;;
  recoverable) echo 'status: degraded done' >&2; exit 2 ;;
  remote-timeout) exit 124 ;;
  remote-255)
    echo 'cloud-init failed after Connection reset by peer while reading metadata' >&2
    exit 255
    ;;
esac
EOF
  chmod 755 "$fixture/fake ssh" "$fixture/cloud-init"
}
run_readiness() {
  export FAKE_SSH_MODE=${2:-execute} FAKE_CLOUD_INIT_MODE=${3:-success}
  status=0
  timeout "$(( $1 + 5 ))" bash -c 'source "$1"; shift; wait_for_cloud_init "$@"' \
    'readiness test' "$fixture/helper with spaces.sh" "$1" "$fixture/fake ssh" \
    --fixture-option 'value with spaces' >"$fixture/stdout" 2>"$fixture/stderr" || status=$?
}
cloud_init_count() { if [[ -f $FAKE_CLOUD_INIT_CALLS ]]; then wc -l <"$FAKE_CLOUD_INIT_CALLS"; else echo 0; fi; }
ssh_remote_commands() {
  # Each invocation ends with its remote command, a NUL, and a newline.
  local value command=
  [[ -f $FAKE_SSH_CALLS ]] || return 0
  while IFS= read -r -d '' value; do
    value=${value#$'\n'}
    if [[ $value == timeout\ * ]]; then command=$value; printf '%s\n' "$command"; fi
  done <"$FAKE_SSH_CALLS"
}
transport_reset() {
  run_readiness 5 reset-once
  [[ $status == 0 ]]
  diff <(printf 'status: done\n') "$fixture/stdout"
  grep -F kex_exchange_identification "$fixture/stderr"
  grep -F retrying "$fixture/stderr"
  [[ $(cloud_init_count) == 1 ]]
  mapfile -t commands < <(ssh_remote_commands)
  ((${#commands[@]} >= 2))
  previous=5
  for command in "${commands[@]}"; do
    [[ $command =~ ^timeout\ ([0-9]+)\ cloud-init\ status\ --wait$ ]]
    value=${BASH_REMATCH[1]}
    ((value > 0 && value <= 5 && value <= previous))
    previous=$value
  done
  # Read NUL-delimited arguments without losing spaces.
  found=false
  while IFS= read -r -d '' argument; do
    if [[ $argument == 'value with spaces' ]]; then found=true; fi
  done <"$FAKE_SSH_CALLS"
  [[ $found == true ]]
}
cloud_init_failure() {
  for mode in critical recoverable; do
    run_readiness 5 execute "$mode"
    if [[ $mode == critical ]]; then [[ $status == 1 ]]; else [[ $status == 2 ]]; fi
    [[ $(cloud_init_count) == 1 ]]
    rm "$FAKE_CLOUD_INIT_CALLS" "$FAKE_SSH_CALLS"
  done
}
remote_timeout() {
  run_readiness 5 execute remote-timeout
  [[ $status == 124 ]]
  grep -F 'Timed out' "$fixture/stderr"
  [[ $(cloud_init_count) == 1 && $(ssh_remote_commands | wc -l) == 1 ]]
}
nontransport_255() {
  run_readiness 5 execute remote-255
  [[ $status == 255 ]]
  grep -F 'Connection reset by peer' "$fixture/stderr"
  reject grep -F retrying "$fixture/stderr"
  [[ $(cloud_init_count) == 1 && $(ssh_remote_commands | wc -l) == 1 ]]
}
zero_budget() {
  run_readiness 0
  [[ $status == 124 ]]
  grep -F 'deadline expired' "$fixture/stderr"
  test ! -e "$FAKE_SSH_CALLS"
}
hanging_ssh() {
  run_readiness 1 hang
  [[ $status == 124 ]]
  grep -F 'Timed out' "$fixture/stderr"
  test ! -e "$FAKE_CLOUD_INIT_CALLS"
}
for case in transport_reset cloud_init_failure remote_timeout nontransport_255 zero_budget hanging_ssh; do
  (
    fixture=$(mktemp -d "${TMPDIR:-/tmp}/distro readiness with spaces.XXXXXXXX")
    trap 'rm -rf -- "$fixture"' EXIT
    export PATH="$fixture:$PATH"
    setup
    "$case"
    echo "PASS: $case"
  )
done
