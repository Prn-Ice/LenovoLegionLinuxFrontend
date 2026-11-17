#!/usr/bin/env bash
# Check the installed Nix package and its portable helper inside the VM.
# shellcheck disable=SC2016
set -euo pipefail
# shellcheck source=control/test/portable_session_test.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/portable_session_test.sh"
declare -A app=()
frontend=$1 bundle=$1/app/legion-linux-frontend
wait_until 30 systemctl is-active polkit.service
echo 'Checking desktop metadata and disabled services'
test -f "$frontend/share/applications/io.github.prnice.legion_linux_frontend.desktop"
test -f "$frontend/share/metainfo/io.github.prnice.legion_linux_frontend.metainfo.xml"
test -f "$bundle/share/licenses/legion_frontend/THIRD_PARTY_NOTICES.md"
test -x "$bundle/libexec/legion-portable-control"
test ! -d "$bundle/lib/systemd"
test ! -d "$bundle/share/polkit-1"
test ! -d "$bundle/share/dbus-1"
reject systemctl cat legion-control.service
reject systemctl cat legion-telemetry.service
echo 'Checking the public launcher renders a Flutter window'
as_user approved xvfb-run -a -s '-screen 0 1280x800x24' bash -c '
  export LIBGL_ALWAYS_SOFTWARE=1 GSETTINGS_BACKEND=memory
  dbus-run-session -- legion_frontend >/home/approved/gui.log 2>&1 &
  app=$!
  trap '\''kill "$app" 2>/dev/null || true'\'' EXIT
  xdotool search --sync --onlyvisible --class io.github.prnice.legion_linux_frontend >/home/approved/window.id
  xdotool getwindowpid "$(head -n1 /home/approved/window.id)" >/home/approved/app.pid
  wait "$app"
' >/home/approved/display.log 2>&1 &
wait_until 60 test -s /home/approved/app.pid
pid=$(cat /home/approved/app.pid)
executable=$(readlink -f "/proc/$pid/exe")
[[ $executable == "$bundle/"* ]]
test -x "${executable%/*}/libexec/legion-portable-control"
kill "$pid"
echo 'Checking synthetic helper write, readback, restore, and cleanup'
session_new app approved "$bundle/libexec/legion-portable-control" false
[[ ${app[cli]} == "$(readlink -f /run/current-system/sw/bin/legion_cli)" ]]
session_prepare app success
session_send app connect
session_send app authorize
session_send app enable
printf 'enabled\n' | diff - <(session_value app battery-conservation)
session_send app disable
printf 'disabled\n' | diff - <(session_value app battery-conservation)
session_close app
wait_collected 'legion-portable-control-*' 8
