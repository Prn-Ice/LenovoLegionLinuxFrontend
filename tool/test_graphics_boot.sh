#!/usr/bin/env bash
# Exercise real persistence and locking with only local command/DRM fixtures.
set -euo pipefail
umask 077
SOURCE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/packaging/nixos/legion-graphics-boot.sh
ROOT=$(mktemp -d -t legion-boot-test-XXXXXX)
trap 'rm -rf -- "$ROOT"' EXIT
OLD_BOOT=11111111-1111-4111-8111-111111111111
NEW_BOOT=22222222-2222-4222-8222-222222222222
REAL_SYNC=$(command -v sync)
REAL_MV=$(command -v mv)
REAL_TIMEOUT=$(command -v timeout)
export REAL_SYNC REAL_MV REAL_TIMEOUT
mkdir "$ROOT/mock"
cat > "$ROOT/mock/dispatch" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
name=${0##*/}
printf '%s %s\n' "$name" "$*" >> "$TEST_ROOT/calls"
case "$name" in
  date) cat "$TEST_ROOT/clock" ;;
  timeout)
    [[ $1 == --signal=KILL && $2 == 40s ]] || exit 99
    if [[ ${TEST_TIMEOUT:-0} == 1 && ( -z ${TEST_TIMEOUT_NAME:-} || ${3##*/} == "$TEST_TIMEOUT_NAME" ) ]]; then exit 124; fi
    exec "$REAL_TIMEOUT" "$@"
    ;;
  sync)
    if [[ ${TEST_IO_FAILURE:-} == sync_file && -f $2 ]]; then exit 1; fi
    if [[ ${TEST_IO_FAILURE:-} == sync_directory && -d $2 ]]; then exit 1; fi
    exec "$REAL_SYNC" "$@"
    ;;
  mv)
    [[ ${TEST_IO_FAILURE:-} != rename ]] || exit 1
    exec "$REAL_MV" "$@"
    ;;
  systemctl)
    case "$1" in
      is-system-running) cat "$TEST_ROOT/manager"; exit 1 ;;
      list-units) cat "$TEST_ROOT/users" ;;
      *) exit 99 ;;
    esac
    ;;
  cli)
    if [[ ${TEST_REQUIRE_APPLY:-0} == 1 ]]; then
      jq -e '.phase == "applying"' "$TEST_ROOT/state/request.json" > /dev/null
    fi
    if [[ ${TEST_CRASH:-0} == 1 ]]; then kill -KILL "$TEST_PROCESS_ID"; exit 1; fi
    case "$3" in
      status)
        if [[ -e $TEST_ROOT/status-seen ]]; then cat "$TEST_ROOT/after";
        else touch "$TEST_ROOT/status-seen"; cat "$TEST_ROOT/before"; fi
        ;;
      set)
        if [[ ${TEST_FAILURE:-} == set ]]; then
          printf 'backend refused newly opened NVIDIA client\n' >&2
          exit 1
        fi
        ;;
      reconcile) [[ ${TEST_FAILURE:-} != reconcile ]] ;;
      *) exit 99 ;;
    esac
    ;;
  lifecycle) [[ ${TEST_FAILURE:-} != cleanup ]] ;;
  *) exit 99 ;;
esac
SH
chmod +x "$ROOT/mock/dispatch"
for command in date timeout sync mv systemctl cli lifecycle; do
  ln -s dispatch "$ROOT/mock/$command"
done
export PATH="$ROOT/mock:$PATH"

graphics() {
  local mode=${1:-hybrid} effective=attached
  if [[ $mode == hybrid-igpu-only ]]; then effective=detached; fi
  jq -cn --arg mode "$mode" --arg effective "$effective" '{
    schema_version:1, selected_mode:$mode, expected_dgpu_state:$effective,
    effective_dgpu_state:$effective, reconciliation:"settled",
    client_inspection_complete:true, active_clients:[],
    available_modes:["hybrid","hybrid-igpu-only"]}'
}
setup() {
  TEST_ROOT=$(mktemp -d "$ROOT/case-XXXXXX")
  export TEST_ROOT TEST_REQUIRE_APPLY=0 TEST_FAILURE='' TEST_TIMEOUT=0 TEST_TIMEOUT_NAME='' TEST_CRASH=0 TEST_IO_FAILURE=''
  mkdir -m 700 "$TEST_ROOT/state" "$TEST_ROOT/drm"
  mkdir "$TEST_ROOT/drm/card0-eDP-1"
  printf 'connected\n' > "$TEST_ROOT/drm/card0-eDP-1/status"
  printf '%s\n' "$OLD_BOOT" > "$TEST_ROOT/boot-id"
  printf '100000.5\n' > "$TEST_ROOT/clock"
  printf 'starting\n' > "$TEST_ROOT/manager"
  : > "$TEST_ROOT/users"
  : > "$TEST_ROOT/calls"
  graphics > "$TEST_ROOT/before"
  graphics hybrid-igpu-only > "$TEST_ROOT/after"
  sed -e "s|^STATE_DIR=.*|STATE_DIR=$TEST_ROOT/state|" \
    -e "s|^BOOT_ID_PATH=.*|BOOT_ID_PATH=$TEST_ROOT/boot-id|" \
    -e "s|^DRM_ROOT=.*|DRM_ROOT=$TEST_ROOT/drm|" \
    -e "s|^ROOT_UID=.*|ROOT_UID=$UID|" \
    -e "s|@cli@|$ROOT/mock/cli|g" \
    -e "s|@lifecycle@|$ROOT/mock/lifecycle|g" \
    -e 's|@modprobe@|/unused-modprobe|g' \
    -e "s|@systemctl@|$ROOT/mock/systemctl|g" "$SOURCE" > "$TEST_ROOT/helper"
}
run_ok() {
  if ! bash "$TEST_ROOT/helper" "$@" > "$TEST_ROOT/output" 2> "$TEST_ROOT/error"; then
    cat "$TEST_ROOT/error" >&2; return 1
  fi
}
run_bad() {
  if bash "$TEST_ROOT/helper" "$@" > "$TEST_ROOT/output" 2> "$TEST_ROOT/error"; then
    printf 'Expected failure: %s\n' "$*" >&2; return 1
  fi
}
phase_is() { jq -e --arg phase "$1" '.phase == $phase' "$TEST_ROOT/state/request.json" > /dev/null; }
no_hardware() { ! grep -Eq '^(cli|lifecycle) ' "$TEST_ROOT/calls"; }
no_commands() { [[ ! -s $TEST_ROOT/calls ]]; }
no_selection() { ! grep -q '^cli .* set ' "$TEST_ROOT/calls"; }
queue() {
  run_ok request "${1:-hybrid-igpu-only}"
  printf '%s\n' "$NEW_BOOT" > "$TEST_ROOT/boot-id"
  : > "$TEST_ROOT/calls"
  rm -f "$TEST_ROOT/status-seen"
}
change_json() {
  jq "$2" "$1" > "$TEST_ROOT/changed"
  "$REAL_MV" "$TEST_ROOT/changed" "$1"
}
pass() { printf 'PASS: %s\n' "$1"; }

setup
run_ok request hybrid-igpu-only
phase_is pending
[[ $(stat -c %a "$TEST_ROOT/state/request.json") == 600 ]]
run_ok cancel
phase_is cancelled
no_hardware
# Verify fsync(file), rename, fsync(directory) for both atomic updates.
grep -E '^(sync|mv) ' "$TEST_ROOT/calls" | sed "s|$TEST_ROOT/state|STATE|g; s|.request-[[:alnum:]]*|TEMP|g" > "$TEST_ROOT/writes"
printf '%s\n' 'sync -- STATE/TEMP' 'mv -fT -- STATE/TEMP STATE/request.json' 'sync -- STATE' \
  'sync -- STATE/TEMP' 'mv -fT -- STATE/TEMP STATE/request.json' 'sync -- STATE' > "$TEST_ROOT/expected"
diff -u "$TEST_ROOT/expected" "$TEST_ROOT/writes"
pass 'queue/cancel are private, durable, atomic, and hardware-free'

setup
for mode in discrete hybrid-auto '' ../hybrid 'hybrid;reboot'; do run_bad request "$mode"; done
run_bad request hybrid extra
run_bad status extra
run_bad unknown
no_hardware
pass 'modes and argument counts are restricted'

setup
run_ok request hybrid-igpu-only
: > "$TEST_ROOT/calls"
run_ok boot
jq -e '.phase == "deferred"' "$TEST_ROOT/output" > /dev/null
phase_is pending
[[ $(wc -l < "$TEST_ROOT/calls") == 2 ]]
no_hardware
pass 'same-boot request stays pending'

setup
queue
for manager in running degraded maintenance stopping unknown; do
  printf '%s\n' "$manager" > "$TEST_ROOT/manager"
  run_ok boot
  jq -e '.phase == "deferred"' "$TEST_ROOT/output" > /dev/null
done
no_hardware
phase_is pending
pass 'live activation never runs hardware commands'

setup
queue
export TEST_REQUIRE_APPLY=1
run_ok boot
phase_is completed
jq -e --slurpfile after "$TEST_ROOT/after" '.final_status == $after[0]' "$TEST_ROOT/state/request.json" > /dev/null
[[ $(grep -c '^cli .* set ' "$TEST_ROOT/calls") == 1 ]]
export TEST_REQUIRE_APPLY=0
run_ok boot
[[ $(grep -c '^cli .* set ' "$TEST_ROOT/calls") == 1 ]]
pass 'request is consumed before CLI calls, verified, and selected once'

setup
queue
printf 'user@1000.service loaded active running\n' > "$TEST_ROOT/users"
run_bad boot
grep -q 'user manager' "$TEST_ROOT/error"
phase_is failed
no_hardware
pass 'running user managers block before hardware'

for clock in 186401.5 99999.5; do
  setup; queue
  printf '%s\n' "$clock" > "$TEST_ROOT/clock"
  run_bad boot
  grep -q expired "$TEST_ROOT/error"
  phase_is failed
  no_hardware
done
pass 'expired and future requests block before hardware'

setup; queue
mkdir "$TEST_ROOT/drm/card1-HDMI-A-1"
printf 'connected\n' > "$TEST_ROOT/drm/card1-HDMI-A-1/status"
run_bad boot
grep -q 'external displays' "$TEST_ROOT/error"
no_selection
pass 'external display blocks ejection'

setup; queue
printf 'disconnected\n' > "$TEST_ROOT/drm/card0-eDP-1/status"
run_bad boot
grep -q 'internal eDP' "$TEST_ROOT/error"
no_selection
pass 'connected internal panel is required'

for change in '.active_clients=[{pid:42}]' '.client_inspection_complete=false' '.active_clients=null' '.active_clients={}' '.client_inspection_complete=1'; do
  setup; queue
  change_json "$TEST_ROOT/before" "$change"
  run_bad boot
  no_selection
  phase_is failed
done
pass 'active clients and incomplete/malformed inspection block selection'

for change in '.available_modes=["hybrid"]' '.selected_mode="discrete"' '.available_modes="hybrid-igpu-only"'; do
  setup; queue
  change_json "$TEST_ROOT/before" "$change"
  run_bad boot
  no_selection
done
pass 'unsupported modes and non-Hybrid policies block selection'

setup; queue
export TEST_FAILURE=set
run_bad boot
grep -q 'newly opened' "$TEST_ROOT/error"
phase_is failed
cp "$TEST_ROOT/calls" "$TEST_ROOT/previous-calls"
run_bad boot
run_bad cancel
diff -u "$TEST_ROOT/previous-calls" "$TEST_ROOT/calls"
pass 'late backend refusal is never retried or cleared by cancellation'

for failure in cleanup reconcile; do
  setup; queue
  export TEST_FAILURE=$failure
  run_bad boot
  phase_is failed
done
pass 'cleanup and reconciliation failures block success'

for change in '.selected_mode="hybrid"' '.expected_dgpu_state="attached"' '.effective_dgpu_state="attached"' '.reconciliation="needed"' '.active_clients=[{pid:42}]' '.client_inspection_complete=false'; do
  setup; queue
  change_json "$TEST_ROOT/after" "$change"
  run_bad boot
  phase_is failed
done
pass 'final readback requires settled requested topology and zero inspected clients'

setup; queue
change_json "$TEST_ROOT/state/request.json" '.phase="applying"'
run_bad boot
no_hardware
run_ok request hybrid
printf '33333333-3333-4333-8333-333333333333\n' > "$TEST_ROOT/boot-id"
graphics > "$TEST_ROOT/after"
run_ok boot
phase_is completed
pass 'interrupted attempts require an explicit recovery request'

setup
run_ok boot
jq -e '.phase == "none"' "$TEST_ROOT/output" > /dev/null
grep -E '^(systemctl|cli|lifecycle) ' "$TEST_ROOT/calls" > "$TEST_ROOT/actual"
printf '%s\n' 'systemctl is-system-running' 'cli --donotexpecthwmon graphics-mode reconcile --json' \
  "lifecycle $ROOT/mock/cli cleanup /unused-modprobe" > "$TEST_ROOT/expected"
diff -u "$TEST_ROOT/expected" "$TEST_ROOT/actual"
pass 'no request preserves ordinary reconcile and cleanup'

for text in 'not-json' '[]' '{"phase":"unknown"}' '{} {}'; do
  setup
  printf '%s\n' "$text" > "$TEST_ROOT/state/request.json"
  run_bad boot
  no_commands
done
for change in '.requested_at=true' '.requested_at=null' '.requested_at="100000"' '.requested_at=1e999' '.requested_boot_id="invalid"' '.requested_boot_id += "\n"' '.mode="discrete"'; do
  setup; queue
  change_json "$TEST_ROOT/state/request.json" "$change"
  run_bad boot
  no_commands
done
setup
head -c 65537 /dev/zero | tr '\0' x > "$TEST_ROOT/state/request.json"
run_bad boot
no_commands
pass 'invalid JSON, phase, size, timestamps, and UUIDs refuse before hardware'

for text in '[]' '{}' '{"schema_version":true}' '{} {}' 'not-json'; do
  setup; queue
  printf '%s\n' "$text" > "$TEST_ROOT/before"
  run_bad boot
  no_selection
done
pass 'invalid authoritative status refuses selection'

setup; queue
chmod 755 "$TEST_ROOT/state"
run_bad boot
no_hardware
chmod 700 "$TEST_ROOT/state"
chmod 644 "$TEST_ROOT/state/request.json"
run_bad boot
no_hardware
pass 'private state ownership and permissions are enforced'

setup
ln -s "$TEST_ROOT/before" "$TEST_ROOT/state/request.json"
run_bad boot
no_hardware
rm "$TEST_ROOT/state/request.json"
rm "$TEST_ROOT/state/lock"
ln -s "$TEST_ROOT/before" "$TEST_ROOT/state/lock"
run_bad boot
no_hardware
pass 'state and lock symlinks are refused'

setup; queue
exec 8>> "$TEST_ROOT/state/lock"
flock --exclusive --nonblock 8
run_bad boot
grep -q 'holds the lock' "$TEST_ROOT/error"
no_hardware
flock --unlock 8
exec 8>&-
pass 'concurrent operations fail on the nonblocking lock'

setup; queue
export TEST_TIMEOUT=1
run_bad boot
no_hardware
phase_is pending
pass 'system startup query timeout cannot start a transition'

for command in cli lifecycle; do
  setup; queue
  export TEST_TIMEOUT=1 TEST_TIMEOUT_NAME=$command
  run_bad boot
  phase_is failed
  cp "$TEST_ROOT/calls" "$TEST_ROOT/previous-calls"
  run_bad boot
  diff -u "$TEST_ROOT/previous-calls" "$TEST_ROOT/calls"
done
pass 'hardware-command deadlines consume the attempt and never retry'

for failure in sync_file rename sync_directory; do
  setup; queue
  export TEST_IO_FAILURE=$failure
  run_bad boot
  no_hardware
  if [[ $failure == sync_directory ]]; then phase_is applying; else phase_is pending; fi
  shopt -s nullglob
  temporary_files=("$TEST_ROOT/state"/.request-*)
  [[ ${#temporary_files[@]} == 0 ]]
done
pass 'failed fsync or rename blocks hardware and removes temporary files'

setup; queue
export TEST_CRASH=1
if bash -c 'export TEST_PROCESS_ID=$$; exec bash "$TEST_ROOT/helper" boot' > "$TEST_ROOT/output" 2> "$TEST_ROOT/error"; then
  printf 'Expected simulated crash\n' >&2; exit 1
fi
phase_is applying
export TEST_CRASH=0
cp "$TEST_ROOT/calls" "$TEST_ROOT/previous-calls"
run_bad boot
diff -u "$TEST_ROOT/previous-calls" "$TEST_ROOT/calls"
pass 'process death leaves durable consumption and blocks later retries'
