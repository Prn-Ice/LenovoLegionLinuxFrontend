#!/usr/bin/env bash
# Test sealed launch, peer authentication, and cleanup inside the NixOS VM.
# shellcheck disable=SC2016
set -euo pipefail
# shellcheck source=control/test/portable_session_test.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/portable_session_test.sh"
# Session helpers access these maps by name.
# shellcheck disable=SC2034
declare -A app=() first=() second=()
probe=$1 fixtures=$2
# Keep diagnostics visible when a rejected command redirects its own stderr.
exec 3>&2
report_failure() {
  local status=$?
  if ((status != 0)); then
    printf 'Portable bootstrap test failed with status %s.\n' "$status" >&2
    cat /home/approved/production.{out,err} >&2 || true
    journalctl -b --no-pager -n 60 >&2 || true
  fi
} >&3
trap report_failure EXIT
wait_until 30 systemctl is-active polkit.service
as_user approved executable-snapshot-test >/tmp/user-snapshot.out
reject grep -F '# SKIP' /tmp/user-snapshot.out
executable-snapshot-test >/tmp/root-snapshot.out
reject grep -F '# SKIP' /tmp/root-snapshot.out
grep -F /snapshot/root-alias-crossing-user-directory /tmp/root-snapshot.out
as_user approved portable-lifetime-test
trusted-executable-test >/tmp/trust.out
reject grep -F '# SKIP' /tmp/trust.out
stage() {
  local user=$1 directory="/home/$1/AppImage with spaces"
  binary=$directory/portable-bootstrap-probe
  as_user "$user" mkdir -p "$directory"
  as_user "$user" rm -f "$binary"
  as_user "$user" cp "$probe/bin/portable-bootstrap-probe" "$binary"
  as_user "$user" chmod 700 "$binary"
}
launch() {
  local user=${1:-approved} option=${2:-} gated=${3:-false} ready
  stage "$user"
  output=/home/$user/bootstrap.out fifo=/home/$user/bootstrap.in
  if [[ $gated == true ]]; then
    as_user "$user" rm -f "$fifo"
    as_user "$user" mkfifo "$fifo"
  fi
  as_user "$user" bash -c '
    export LD_LIBRARY_PATH=/nonexistent/appimage/lib GIO_EXTRA_MODULES=/nonexistent/appimage/modules DBUS_SYSTEM_BUS_ADDRESS=unix:path=/nonexistent/appimage/bus
    if [[ $3 == true ]]; then exec 0<>"$4"; fi
    if [[ -n $2 ]]; then exec "$1" "$2"; else exec "$1"; fi
  ' bash "$binary" "$option" "$gated" "$fifo" >"$output" 2>"$output.err" &
  wait_until 10 grep SNAPSHOT_READY "$output"
  ready=$(cat "$output")
  [[ $ready =~ launcher=([0-9]+) ]] || fail "$ready"
  pid=${BASH_REMATCH[1]}
  [[ $ready =~ unit=([^[:space:]]+) ]] || fail "$ready"
  unit=${BASH_REMATCH[1]}
}
collected() { wait_collected 'legion-bootstrap-probe-*' 8; }
root_helper() {
  local text
  wait_until 10 grep 'ROOT_HELPER uid=0' "$output"
  text=$(cat "$output")
  [[ $text == *sealed=yes* && $text =~ ROOT_HELPER\ uid=0\ pid=([0-9]+) ]] || fail "$text"
  helper=${BASH_REMATCH[1]}
}
echo 'Checking authorized startup from a user-owned path containing spaces'
launch
root_helper
executable=$(systemctl show --property=ExecStart --value "$unit")
[[ $executable == */proc/self/fd/0* && $executable != *"/proc/$pid/fd/"* ]]
reject as_user approved ls "/proc/$pid/fd"
test -e "/proc/$helper"
kill -TERM "$pid"
assert_gone "$helper" 5
collected
echo 'Checking app-parent death ends the launcher and root helper'
launch
root_helper
parent=$(awk '{print $4}' "/proc/$pid/stat")
((parent > 1))
kill -KILL "$parent"
assert_gone "$helper" 5
collected
echo 'Checking source replacement cannot change the approved snapshot'
launch approved --wait-before-start true
as_user approved mv "$binary" "$binary.old"
as_user approved bash -c 'printf "#!/bin/sh\nexit 99\n" >"$1"' bash "$binary"
as_user approved bash -c 'printf s >"$1"' bash "$fifo"
root_helper
kill -KILL "$pid"
assert_gone "$helper" 5
collected
echo 'Checking denied approval and a missing authentication agent'
for user in denied challenge; do
  stage "$user"
  output=/home/$user/denied.out
  reject as_user "$user" "$binary" >"$output" 2>"$output.err"
  reject grep ROOT_HELPER "$output"
  grep '[^[:space:]]' "$output.err"
  collected
done
echo 'Checking launcher death cancels a helper still waiting to start'
for signal in TERM KILL; do
  launch approved --queue-behind-gate
  wait_until 10 grep START_ACKNOWLEDGED "$output"
  [[ $(systemctl show --property=ActiveState --value "$unit") == inactive ]]
  reject grep ROOT_HELPER "$output"
  kill -"$signal" "$pid"
  collected
  systemctl stop legion-bootstrap-gate.service
  reject grep ROOT_HELPER "$output"
done
echo 'Checking a late helper refuses handles from an exited launcher'
launch approved --queue-behind-gate
wait_until 10 grep START_ACKNOWLEDGED "$output"
kill -KILL "$pid"
systemctl kill --kill-whom=main --signal=USR1 legion-bootstrap-gate.service
collected
reject grep ROOT_HELPER "$output"
echo 'Checking native peer connection deadlines and cancellation'
index=0
for mode in timeout cancel; do
  printf -v unit 'legion-bootstrap-probe-01234567-89ab-4cde-8fab-%012d.service' "$index"
  index=$((index + 1))
  socket=/run/legion-stalled-peer.sock output=/tmp/stalled-peer.out
  rm -f "$socket" "$output"
  systemd-run --quiet --collect --service-type=exec --unit="$unit" --property=RuntimeMaxSec=15 --property=StandardOutput=append:"$output" "$fixtures/bin/legion-portable-test-client" --stall-peer "$socket"
  wait_until 5 grep FAKE_READY "$output"
  helper=$(systemctl show --property=MainPID --value "$unit")
  text=$(cat "$output")
  [[ $text =~ bus=([^[:space:]]+) ]]
  bus=${BASH_REMATCH[1]}
  if [[ $mode == timeout ]]; then
    as_user approved legion-portable-test-client --connection-timeout "unix:path=$socket" "$unit" "$helper" "$bus"
  else
    as_user approved legion-portable-test-client --connection-cancel "unix:path=$socket" "$unit" "$helper" "$bus" >/home/approved/connect.out 2>/home/approved/connect.err &
    wait_until 4 grep AUTH_SEEN "$output"
    text=$(cat /home/approved/connect.out)
    [[ $text =~ CONNECTING\ pid=([0-9]+) ]] || fail "$text"
    kill -USR1 "${BASH_REMATCH[1]}"
    wait_until 3 grep CONNECTION_ENDED /home/approved/connect.out
  fi
  wait_until 3 grep AUTH_CLOSED "$output"
  collected
done
echo 'Checking a user service cannot impersonate the root helper'
unit=legion-bootstrap-probe-01234567-89ab-4cde-8fab-999999999999.service
socket=/home/approved/user-service.sock output=/tmp/user-service-peer.out
systemd-run --quiet --collect --service-type=exec --unit="$unit" --property=User=approved --property=RuntimeMaxSec=15 --property=StandardOutput=append:"$output" "$fixtures/bin/legion-portable-test-client" --fake-peer "$socket"
wait_until 5 grep FAKE_READY "$output"
helper=$(systemctl show --property=MainPID --value "$unit")
text=$(cat "$output")
[[ $text =~ bus=([^[:space:]]+) ]]
expect_status 8 as_user approved legion-portable-test-client --intrude "unix:path=$socket" "$unit" "$helper" "${BASH_REMATCH[1]}"
reject grep FAKE_CLOSED_BEFORE_AUTH "$output"
systemctl stop "$unit"
collected
echo 'Checking approved root peer validates and applies typed commands'
session_new app approved "$probe/bin/portable-bootstrap-probe"
session_prepare app success
manager_owner=$(busctl --system call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus GetNameOwner s org.freedesktop.systemd1 | cut -d '"' -f2)
expect_status 8 as_user approved legion-portable-test-client --intrude "${app[address]}" "${app[unit]}" "${app[helper]}" "$manager_owner"
as_user approved legion-portable-test-client --fake-peer /home/approved/fake.sock >/tmp/fake-peer.out 2>/tmp/fake-peer.err &
wait_until 5 grep FAKE_READY /tmp/fake-peer.out
expect_status 8 as_user approved legion-portable-test-client --intrude unix:path=/home/approved/fake.sock "${app[unit]}" "${app[helper]}" "${app[bus_name]}"
wait_until 5 grep FAKE_CLOSED_BEFORE_AUTH /tmp/fake-peer.out
# Other processes must fail EXTERNAL authentication before methods are exported.
for user in approved denied; do
  expect_status 7 as_user "$user" legion-portable-test-client --intrude "${app[address]}" "${app[unit]}" "${app[helper]}" "${app[bus_name]}"
done
session_send app connect
expect_status 8 as_user approved legion-portable-test-client --intrude "${app[address]}" "${app[unit]}" "${app[helper]}" "${app[bus_name]}"
session_send app enable org.freedesktop.DBus.Error.AccessDenied
session_send app authorize
session_send app invalid org.freedesktop.DBus.Error.InvalidArgs
session_send app persistent io.github.prnice.LegionControl1.Error.NotSupported
session_send app enable
printf 'enabled\n' | diff - <(session_value app battery-conservation)
session_send app disable
printf 'disabled\n' | diff - <(session_value app battery-conservation)
session_send app fan
printf 'synthetic fan data\n' | diff - <(session_value app payload-read)
session_private app bash -c 'test -z "$(find /tmp -maxdepth 1 -name "legion-control-*" -type f -print)"'
session_close app
collected
echo 'Checking idle private peer shuts down'
session_new app approved "$probe/bin/portable-bootstrap-probe"
session_send app connect
session_send app idle
wait_until 8 test ! -e "${app[runtime]}"
session_close app
collected
echo 'Checking helper crash keeps other helpers blocked through backend cleanup'
session_new first approved "$probe/bin/portable-bootstrap-probe"
session_prepare first tree
session_send first connect
session_send first authorize
session_begin first enable
session_wait_tree first
session_new second approved "$probe/bin/portable-bootstrap-probe"
session_prepare second success
session_send second connect
session_send second authorize
session_send second enable io.github.prnice.LegionControl1.Error.Busy
kill -KILL "${first[helper]}"
# systemd retains the descriptor and lock until resistant descendants are killed.
reject flock -n /run/legion-control/operation.lock true
session_send second enable io.github.prnice.LegionControl1.Error.Busy
assert_gone "${first[pids]}" 5
wait_until 5 flock -n /run/legion-control/operation.lock true
session_send second enable
session_close second
session_close first
collected
echo 'Checking production entry points reject root launch and unsealed cleanup'
reject "$probe/bin/legion-portable-control" --control
reject "$probe/bin/legion-portable-control" --cleanup
reject as_user approved "$probe/bin/legion-portable-control" --cleanup
reject as_user approved "$probe/bin/legion-portable-control" --wait-before-start
echo 'Checking production CLI discovery and typed writes'
session_new app approved "$probe/bin/legion-portable-control"
[[ ${app[unit]} == legion-portable-control-* ]]
[[ ${app[cli]} == "$(readlink -f /run/current-system/sw/bin/legion_cli)" ]]
session_prepare app success
session_send app connect
session_send app authorize
session_send app resume-after-idle
session_send app enable
printf 'enabled\n' | diff - <(session_value app battery-conservation)
session_send app disable
printf 'disabled\n' | diff - <(session_value app battery-conservation)
session_close app
wait_collected 'legion-portable-control-*' 8
echo 'Checking production startup rejects incompatible and failed CLI help'
for mode in missing fail flood hang; do
  printf '%s\n' "$mode" >/run/legion-cli-help-mode
  reject as_user approved "$probe/bin/legion-portable-control" --control >/home/approved/production.out 2>/home/approved/production.err
  if ! grep -F 'CONTROL_SETUP_ERROR ' /home/approved/production.out; then
    cat /home/approved/production.{out,err} >&2
    stat /run/legion-cli-help-mode >&2
    fail "Missing setup error for CLI help mode: $mode"
  fi
  reject grep -F 'CONTROL_READY ' /home/approved/production.out
  wait_collected 'legion-portable-control-*' 8
  rm -f /run/legion-cli-help-mode
done
echo 'Checking production startup respects denial and missing agent'
for user in denied challenge; do
  reject as_user "$user" "$probe/bin/legion-portable-control" --control >"/home/$user/production.out" 2>"/home/$user/production.err"
  reject grep -F 'CONTROL_READY ' "/home/$user/production.out"
  wait_collected 'legion-portable-control-*' 8
done
test ! -e /etc/systemd/system/legion-control.service
test ! -e /run/systemd/system/legion-control.service
assert_cleanup_succeeded
