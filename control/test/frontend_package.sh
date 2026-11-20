#!/usr/bin/env bash
# Check the installed Nix package and its privileged control helper in the VM.
# shellcheck disable=SC2016
set -euo pipefail
support=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=control/test/helper_session_test.sh
source "$support/helper_session_test.sh"
# shellcheck source=control/test/distro_test_support.sh
source "$support/distro_test_support.sh"
assert_disposable_vm
declare -A app=()
frontend=$1 bundle=$1/app/legion-linux-frontend
wait_until 30 systemctl is-active polkit.service
echo 'Checking desktop metadata and disabled services'
test -f "$frontend/share/applications/io.github.prnice.legion_linux_frontend.desktop"
test -f "$frontend/share/metainfo/io.github.prnice.legion_linux_frontend.metainfo.xml"
test -f "$bundle/share/licenses/legion_frontend/THIRD_PARTY_NOTICES.md"
test -x "$bundle/libexec/legion-control-helper"
test ! -d "$bundle/lib/systemd"
test ! -d "$bundle/share/polkit-1"
test ! -d "$bundle/share/dbus-1"
reject systemctl cat legion-control.service
reject systemctl cat legion-telemetry.service
echo 'Checking first-launch administrator access and normal window close'
bash "$support/desktop_test_support.sh" legion_frontend gui.log 'Nix frontend' "$bundle/legion_frontend"
bash "$support/desktop_test_support.sh" legion_frontend power.log "Nix CPU power" "$bundle/legion_frontend" false allow
echo 'Checking synthetic helper write, readback, restore, and cleanup'
session_new app approved "$bundle/libexec/legion-control-helper" false
[[ ${app[cli]} == "$(readlink -f /run/current-system/sw/bin/legion_cli)" ]]
session_prepare app success
session_send app connect
session_send app authorize
session_send app enable
printf 'enabled\n' | diff - <(session_value app battery-conservation)
session_send app disable
printf 'disabled\n' | diff - <(session_value app battery-conservation)
session_close app
wait_collected 'legion-control-helper-*' 8
assert_cleanup_succeeded
