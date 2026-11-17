#!/usr/bin/env bash
# Exercise the production helper against the guest's systemd and Polkit.
set -euo pipefail
# shellcheck source=control/test/portable_session_test.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/portable_session_test.sh"
# shellcheck source=control/test/distro_test_support.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/distro_test_support.sh"
# Session helpers access these maps by name.
# shellcheck disable=SC2034
declare -A app=() first=() second=()
assert_disposable_vm
launcher=/home/approved/legion-portable-control
before=$(mktemp)
persistent_files >"$before"
echo 'Checking root and unsealed entry-point rejection'
reject "$launcher" --control
reject "$launcher" --cleanup
reject as_user approved "$launcher" --cleanup
echo 'Checking approved startup, command validation, synthetic write/readback/restore'
session_new app approved "$launcher"
[[ ${app[cli]} == /usr/local/bin/legion_cli ]]
session_prepare app success
session_send app connect
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
session_close app
wait_collected
echo 'Checking denial and missing authentication agent'
for user in denied challenge; do
  output=/home/$user/production.out
  reject as_user "$user" "/home/$user/legion-portable-control" --control >"$output" 2>"$output.err"
  reject grep -F 'CONTROL_READY ' "$output"
  grep -F 'GDBus.Error:' "$output.err"
  wait_collected
done
echo 'Checking failed, incomplete, flooding, and stalled CLI startup'
for mode in missing fail flood hang; do
  printf '%s\n' "$mode" >/run/legion-cli-help-mode
  output=/home/approved/production.out
  reject as_user approved "$launcher" --control >"$output" 2>"$output.err"
  grep -F 'CONTROL_SETUP_ERROR ' "$output"
  reject grep -F 'CONTROL_READY ' "$output"
  wait_collected
  rm /run/legion-cli-help-mode
done
echo 'Checking crash containment and shared write lock'
session_new first approved "$launcher"
session_prepare first tree
session_send first connect
session_send first authorize
session_begin first enable
session_wait_tree first
session_new second approved "$launcher"
session_prepare second success
session_send second connect
session_send second authorize
session_send second enable io.github.prnice.LegionControl1.Error.Busy
kill -KILL "${first[helper]}"
reject flock -n /run/legion-control/operation.lock true
assert_gone "${first[pids]}" 8
wait_until 8 flock -n /run/legion-control/operation.lock true
session_send second enable
session_send second disable
session_close second
session_close first
wait_collected
diff "$before" <(persistent_files)
rm "$before"
assert_cleanup_succeeded
echo 'PASS: Ubuntu production helper qualification with synthetic hardware'
