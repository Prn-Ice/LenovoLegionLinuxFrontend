#!/usr/bin/env bash
# Exercise managed commands and portable/installed write serialization in the VM.
# shellcheck disable=SC2016
set -euo pipefail
# shellcheck source=control/test/portable_session_test.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/portable_session_test.sh"
declare -A app=()
probe=$1
wait_until 30 systemctl is-active legion-control.service
private() {
  local helper
  helper=$(systemctl show --property=MainPID --value legion-control.service)
  ((helper > 0))
  nsenter --target "$helper" --mount -- "$@"
}
prepare() {
  private bash -c 'mkdir -p /tmp/legion-fixture; rm -f /tmp/legion-fixture/{ready,pids,payload-read}; printf "%s\n" "$1" >/tmp/legion-fixture/mode' bash "$1"
}
collected() { wait_collected 'legion-control-op-*.service' 30; }
start_client() {
  legion-control-test-client "${1:-toggle}" >/tmp/control-client.out 2>/tmp/control-client.err &
  client=$!
}
wait_tree() {
  wait_until 15 private test -f /tmp/legion-fixture/ready
  pids=$(private cat /tmp/legion-fixture/pids)
  local -a tree
  read -r -a tree <<<"${pids//$'\n'/ }"
  [[ ${#tree[@]} == 3 ]] || fail "Expected three backend processes: $pids"
}
echo 'Checking normal completion and private temporary payload'
prepare success
legion-control-test-client toggle
legion-control-test-client fan
printf 'synthetic fan data\n' | diff - <(private cat /tmp/legion-fixture/payload-read)
private bash -c 'test -z "$(find /tmp -maxdepth 1 -name "legion-control-*" -type f -print)"'
collected
echo 'Checking private persistent next-boot graphics state'
legion-control-test-client boot-request >/tmp/boot-pending.json
jq -e '.phase == "pending" and .mode == "hybrid-igpu-only"' /tmp/boot-pending.json
diff <(jq -S . /tmp/boot-pending.json) <(jq -S . /var/lib/legion-graphics-boot/request.json)
[[ $(stat -c '%u:%a' /var/lib/legion-graphics-boot) == 0:700 ]]
diff <(jq -S . /tmp/boot-pending.json) <(legion-control-test-client boot-status | jq -S .)
legion-control-test-client boot-cancel >/tmp/boot-cancelled.json
jq -e '.phase == "cancelled"' /tmp/boot-cancelled.json
diff <(jq -S . /tmp/boot-cancelled.json) <(legion-control-test-client boot-status | jq -S .)
collected
echo 'Checking graphics exit classifications'
for mode in graphics-blocked graphics-pending; do
  prepare "$mode"
  reject legion-control-test-client graphics >/tmp/control-client.out 2>/tmp/control-client.err
  if [[ $mode == graphics-blocked ]]; then error=Error.GraphicsBlocked; else error=Error.GraphicsPending; fi
  grep -F "$error" /tmp/control-client.err
  collected
done
echo 'Checking normal parent exit cleans detached stdout holders'
prepare orphan-stdout
legion-control-test-client toggle
wait_tree
assert_gone "$pids"
collected
echo 'Checking output limit and runtime deadline stop all descendants'
for mode in flood tree; do
  prepare "$mode"
  reject legion-control-test-client toggle >/tmp/control-client.out 2>/tmp/control-client.err
  if [[ $mode == flood ]]; then error=Error.CommandFailed; else error=Error.Timeout; fi
  grep -F "$error" /tmp/control-client.err
  wait_tree
  assert_gone "$pids"
  collected
done
echo 'Checking client SIGKILL cancels the active operation'
prepare tree
start_client
wait_tree
reject legion-control-test-client toggle >/tmp/busy.out 2>/tmp/busy.err
grep -F Error.Busy /tmp/busy.err
kill -KILL "$client"
assert_gone "$pids"
collected
prepare success
legion-control-test-client toggle
echo 'Checking cancelled fan operation removes its temporary payload'
prepare tree
start_client fan
wait_tree
private bash -c 'test -n "$(find /tmp -maxdepth 1 -name "legion-control-*" -type f -print)"'
kill -KILL "$client"
assert_gone "$pids"
collected
private bash -c 'test -z "$(find /tmp -maxdepth 1 -name "legion-control-*" -type f -print)"'
echo 'Checking helper SIGKILL stops its bound operation'
prepare tree
start_client
wait_tree
systemctl kill --kill-whom=main --signal=KILL legion-control.service
assert_gone "$pids"
collected
wait_until 15 systemctl is-active legion-control.service
prepare success
legion-control-test-client toggle
collected
echo 'Checking portable and installed helpers serialize backend writes'
session_new app portable "$probe/bin/portable-bootstrap-probe"
session_prepare app tree
session_send app connect
session_send app authorize
session_begin app enable
session_wait_tree app
prepare success
reject legion-control-test-client toggle >/tmp/shared-busy.out 2>/tmp/shared-busy.err
grep -F Error.Busy /tmp/shared-busy.err
kill -KILL "${app[client]}"
assert_gone "${app[pids]}"
collected
legion-control-test-client toggle
wait_until 8 test ! -e "${app[runtime]}"
systemctl is-active legion-control.service
