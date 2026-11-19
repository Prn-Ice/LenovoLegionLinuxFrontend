#!/usr/bin/env bash
# Check the approved bundled runtime and its cleanup inside the disposable VM.
# shellcheck disable=SC2016
set -euo pipefail
# shellcheck source=control/test/portable_session_test.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/portable_session_test.sh"
probe=$1 invalid_probe=$2
exec > >(tee /tmp/bundled-dart-tests.log) 2>&1
report_failure() {
  local status=$?
  if ((status != 0)); then
    cat /home/approved/bundled-dart.{out,err} || true
    journalctl -b --no-pager -n 100 || true
  fi
}
trap report_failure EXIT

stage() {
  local user=$1 directory="/home/$1/AppImage with spaces"
  binary=$directory/bundled-dart-bootstrap-probe
  as_user "$user" mkdir -p "$directory"
  as_user "$user" rm -f "$binary"
  as_user "$user" cp "$probe/bin/bundled-dart-bootstrap-probe" "$binary"
  as_user "$user" chmod 700 "$binary"
}

launch() {
  local option=${1:---control} ready
  stage approved
  output=/home/approved/bundled-dart.out
  fifo=/home/approved/bundled-dart.in
  as_user approved rm -f "$fifo"
  as_user approved mkfifo "$fifo"
  as_user approved bash -c '
    export LD_LIBRARY_PATH=/untrusted/appimage/lib
    export GIO_EXTRA_MODULES=/untrusted/appimage/modules
    export DBUS_SYSTEM_BUS_ADDRESS=unix:path=/untrusted/appimage/bus
    exec "$1" "$2" <>"$3"
  ' bash "$binary" "$option" "$fifo" >"$output" 2>/home/approved/bundled-dart.err &
  wait_until 10 grep SNAPSHOT_READY "$output"
  ready=$(cat "$output")
  [[ $ready =~ launcher=([0-9]+) ]] || fail "$ready"
  launcher=${BASH_REMATCH[1]}
  [[ $ready =~ unit=([^[:space:]]+) ]] || fail "$ready"
  unit=${BASH_REMATCH[1]}
  runtime=/run/${unit%.service}/dart
}

wait_for_dart() {
  local ready
  wait_until 15 grep DART_BUNDLE_READY "$output"
  ready=$(grep DART_BUNDLE_READY "$output")
  [[ $ready =~ uid=0\ pid=([0-9]+) ]] || fail "$ready"
  helper=${BASH_REMATCH[1]}
  [[ $(systemctl show --property=MainPID --value "$unit") == "$helper" ]]
  [[ $(readlink "/proc/$helper/exe") == "$runtime/lib/ld-linux-x86-64.so.2" ]]
  grep -F '"filePassed": true' "$output"
  grep -F '"peerPassed": true' "$output"
  reject grep DART_BUNDLE_ERROR "$output"
}

wait_for_cleanup() {
  wait_until 8 test ! -e "/run/${unit%.service}"
  wait_collected 'legion-bootstrap-probe-*' 8
  assert_cleanup_succeeded
}

wait_until 30 systemctl is-active polkit.service
echo 'Checking approved Dart startup and protected runtime files'
launch
wait_for_dart
test "$(stat -c '%u:%g:%a' "$runtime")" = '0:0:700'
test "$(find "$runtime" -type f | wc -l)" -eq 7
for file in dartaotruntime lib/ld-linux-x86-64.so.2; do
  test "$(stat -c '%u:%g:%a' "$runtime/$file")" = '0:0:500'
done
for file in helper.aot lib/libc.so.6 lib/libm.so.6 lib/libdl.so.2 lib/libpthread.so.0; do
  test "$(stat -c '%u:%g:%a' "$runtime/$file")" = '0:0:400'
done
reject as_user approved ls "$runtime"
reject as_user approved bash -c 'printf replaced >"$1/helper.aot"' bash "$runtime"
reject as_user approved "$binary" --cleanup
reject "$binary" --cleanup
reject "$binary" --control
echo 'Checking launcher death stops Dart and removes the runtime'
kill -KILL "$launcher"
assert_gone "$helper" 5
grep DART_BUNDLE_EXIT "$output"
wait_for_cleanup

echo 'Checking app-parent death stops Dart and removes the runtime'
launch
wait_for_dart
parent=$(awk '{print $4}' "/proc/$launcher/stat")
((parent > 1))
kill -KILL "$parent"
assert_gone "$helper" 5
wait_for_cleanup

echo 'Checking source replacement cannot change the protected runtime'
launch --wait-before-control
as_user approved mv "$binary" "$binary.old"
as_user approved bash -c 'printf "#!/bin/sh\nexit 99\n" >"$1"' bash "$binary"
as_user approved bash -c 'printf s >"$1"' bash "$fifo"
wait_for_dart
kill -TERM "$launcher"
assert_gone "$helper" 5
wait_for_cleanup

echo 'Checking denial and missing desktop authentication'
for user in denied challenge; do
  stage "$user"
  reject as_user "$user" "$binary" --control >"/home/$user/bundled-denied.out" 2>&1
  reject grep DART_BUNDLE_READY "/home/$user/bundled-denied.out"
  wait_collected 'legion-bootstrap-probe-*' 8
done

echo 'Checking cleanup after the Dart process crashes'
launch
wait_for_dart
kill -KILL "$helper"
wait_for_cleanup

echo 'Checking pre-existing runtime symlinks are rejected without following them'
launch --wait-before-control
mkdir -p "/run/${unit%.service}" /tmp/bundled-dart-symlink-target
printf retained >/tmp/bundled-dart-symlink-target/keep
ln -s /tmp/bundled-dart-symlink-target "$runtime"
as_user approved bash -c 'printf s >"$1"' bash "$fifo"
wait_until 10 grep START_ACKNOWLEDGED "$output"
wait_for_cleanup
reject grep DART_BUNDLE_READY "$output"
grep -F 'DART_BUNDLE_ERROR bundled runtime directory already exists or is unsafe' "$output"
test "$(cat /tmp/bundled-dart-symlink-target/keep)" = retained

echo 'Checking queued startup rejects an exited launcher'
launch --queue-control-behind-gate
wait_until 10 grep START_ACKNOWLEDGED "$output"
reject grep DART_BUNDLE_READY "$output"
kill -KILL "$launcher"
systemctl kill --kill-whom=main --signal=USR1 legion-bootstrap-gate.service
wait_for_cleanup
reject grep DART_BUNDLE_READY "$output"

echo 'Checking failed Dart startup still removes the complete runtime'
probe=$invalid_probe
launch
wait_until 10 grep START_ACKNOWLEDGED "$output"
wait_for_cleanup
grep -F "BUNDLE_READY runtime=$runtime" "$output"
reject grep DART_BUNDLE_READY "$output"
reject grep DART_BUNDLE_ERROR "$output"

echo 'Bundled Dart startup and cleanup checks passed.'
