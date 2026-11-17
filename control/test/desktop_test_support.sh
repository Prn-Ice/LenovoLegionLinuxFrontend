#!/usr/bin/env bash
# Exercise first-launch administrator access against synthetic VM hardware.
# shellcheck disable=SC2016
set -euo pipefail
desktop_support=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=control/test/portable_session_test.sh
source "$desktop_support/portable_session_test.sh"
# shellcheck source=control/test/distro_test_support.sh
source "$desktop_support/distro_test_support.sh"

desktop_prepare_home() {
  mkdir -p "$1/config"
  install -d -m700 "$1/runtime"
  # Hive uses Documents, not XDG_DATA_HOME. Map it to this fresh fixture home.
  printf '%s\n' 'XDG_DOCUMENTS_DIR="$HOME"' >"$1/config/user-dirs.dirs"
}

desktop_ocr() {
  timeout --kill-after=2 15 env OMP_THREAD_LIMIT=1 tesseract "$1" stdout --psm "${2:-7}" 2>/dev/null
}

desktop_scale() {
  if [[ $1 == 11 ]]; then printf '100%%'; else printf '300%%'; fi
}

desktop_check_exit() {
  [[ $1 == 0 ]] || { cat "$2" >&2; fail "Desktop exited with status $1"; }
  reject grep -E 'Pango-CRITICAL|GLib-CRITICAL|GLib-GObject-CRITICAL' "$2"
}

desktop_check_settings() {
  local labels
  labels=$(tr '\n' ' ' <"$1" | tr '[:upper:]' '[:lower:]')
  reject grep -E 'installed service|use on next launch|in use now:' <<<"$labels"
}

gui_desktop() {
  as_user approved env "DISPLAY=$(cat "$gui_home/display")" \
    "XAUTHORITY=$(cat "$gui_home/authority")" "$@"
}

gui_click() {
  printf 'click %s,%s\n' "$1" "$2" >>"$gui_diagnostics"
  gui_desktop xdotool mousemove --sync --window "$(head -n1 "$gui_home/window")" \
    "$1" "$2" getmouselocation --shell click 1 >>"$gui_diagnostics" 2>&1
}

gui_recognize() {
  gui_desktop timeout --kill-after=2 45 bash -e -o pipefail -c '
    source "$1"
    import -window root "$2"
    convert "$2" -crop "$3" -resize "$(desktop_scale "$5")" "$4"
    desktop_ocr "$4" "$5"
  ' bash "$desktop_support/desktop_test_support.sh" "$gui_frame" "$2" "$gui_home/label.png" "${3:-7}" |
    grep -Fi -- "$1"
}

gui_wait_text() { wait_until 30 gui_recognize "$@"; }
desktop_wait_ready() {
  gui_wait_text Dashboard 380x32+288+7
  gui_desktop xdotool windowfocus --sync "$(head -n1 "$gui_home/window")"
  gui_wait_text 'Battery health' 1280x720+0+0 11
}
gui_unit_query() { systemctl list-units --type=service --state=active --plain --no-legend 'legion-portable-control-*' | awk '{print $1}'; }
gui_has_unit() { [[ -n $(gui_unit_query) ]]; }
gui_no_unit() { [[ -z $(gui_unit_query) ]]; }

desktop_verify_cleanup() {
  local pid=$1 helper_pid=$2 unit=$3
  assert_gone "$pid" 10
  assert_gone "$helper_pid" 10
  wait_until 10 test ! -e "/run/${unit%.service}"
  wait_until 10 bash -c 'journalctl -b --no-pager -u "$1" | grep -F "Legion control cleanup complete."' bash "${unit%.service}-cleanup.service"
  wait_until 10 gui_no_unit
  assert_cleanup_succeeded
}

desktop_collect_diagnostics() {
  # An OCR failure must not replace the original app or acceptance failure.
  {
    cat "$gui_log" "$gui_home/display.log" "$gui_home/exit" || true
    ps -eo pid,ppid,user,stat,args
    if [[ -s $gui_home/pid ]]; then
      local pid
      pid=$(cat "$gui_home/pid")
      ls -ld "/proc/$pid" "/proc/$pid/exe" || true
    fi
    gui_desktop xdotool getwindowfocus getmouselocation --shell || true
    desktop_ocr "$gui_home/label.png" 11 || true
    journalctl -b --no-pager -u 'legion-portable-control-*' || true
    journalctl -b --no-pager -k | tail -n100 || true
  } >>"$gui_diagnostics" 2>&1
  cat "$gui_diagnostics" >&2
}

desktop_finish() {
  local status=$? runner
  trap - EXIT
  if ((status != 0)); then desktop_collect_diagnostics || true; fi
  if [[ -s $gui_home/runner ]]; then
    runner=$(cat "$gui_home/runner")
    if [[ $runner =~ ^[0-9]+$ ]]; then
      as_user approved kill -TERM -- "-$runner" 2>/dev/null || true
      for ((attempt=0; attempt<50; attempt++)); do
        as_user approved kill -0 -- "-$runner" 2>/dev/null || break
        sleep 0.1
      done
      as_user approved kill -KILL -- "-$runner" 2>/dev/null || true
    fi
  fi
  if [[ -n ${gui_wrapper:-} ]]; then wait "$gui_wrapper" 2>/dev/null || true; fi
  exit "$status"
}

desktop_launch() {
  assert_vm_marker
  [[ $(id -u) != 0 ]] || fail 'The app must run as the unprivileged fixture user.'
  local home=$1 image=$2 log=$3 app status=0
  printf '%s' "$DISPLAY" >"$home/display"
  printf '%s' "$XAUTHORITY" >"$home/authority"
  "$image" >"$log" 2>&1 &
  app=$!
  # Capture the local PID now; the trap can outlive this function's variables.
  # shellcheck disable=SC2064
  trap "kill $app 2>/dev/null || true" EXIT
  timeout --kill-after=2 120 xdotool search --sync --onlyvisible \
    --class io.github.prnice.legion_linux_frontend >"$home/window"
  xdotool windowsize "$(head -n1 "$home/window")" 1280 720
  xdotool getwindowpid "$(head -n1 "$home/window")" >"$home/pid"
  wait "$app" || status=$?
  printf '%s' "$status" >"$home/exit"
  return "$status"
}

desktop_main() {
  if [[ ${1:-} == --launch ]]; then shift; desktop_launch "$@"; return; fi
  assert_disposable_vm
  local image=$1 log_name=$2 label=$3 expected_executable=${4:-} bundled_libraries=${5:-false}
  local conservation=/sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/conservation_mode
  local pid executable helper_pid unit
  mountpoint -q /sys/bus/platform/drivers || mount -t tmpfs tmpfs /sys/bus/platform/drivers
  mkdir -p "$(dirname "$conservation")"
  echo 0 >"$conservation"
  echo success >/run/legion-gui-fixture-mode
  gui_home=$(as_user approved mktemp -d /home/approved/legion-gui-XXXXXXXX)
  as_user approved bash -c 'source "$1"; desktop_prepare_home "$2"' bash \
    "$desktop_support/desktop_test_support.sh" "$gui_home"
  test ! -e "$gui_home/preferences.hive"
  gui_log=/home/approved/$log_name
  gui_frame=/home/approved/desktop-frame-$label.png
  gui_diagnostics=/home/approved/desktop-diagnostics-$label.txt
  gui_wrapper=
  trap desktop_finish EXIT
  as_user approved bash -c '
    home=$1; shift
    setsid "$@" >"$home/display.log" 2>&1 &
    runner=$!; printf "%s" "$runner" >"$home/runner"
    wait "$runner"
  ' bash "$gui_home" env -u JAVA_HOME -u LD_LIBRARY_PATH \
    "HOME=$gui_home" "XDG_CONFIG_HOME=$gui_home/config" "XDG_DATA_HOME=$gui_home/data" \
    "XDG_RUNTIME_DIR=$gui_home/runtime" GSETTINGS_BACKEND=memory GDK_BACKEND=x11 LIBGL_ALWAYS_SOFTWARE=1 \
    xvfb-run -a -s '-screen 0 1280x900x24' dbus-run-session -- \
    bash "$desktop_support/desktop_test_support.sh" --launch "$gui_home" "$image" "$gui_log" &
  gui_wrapper=$!
  wait_until 120 test -s "$gui_home/pid"
  desktop_wait_ready
  wait_until 10 test -f "$gui_home/preferences.hive"
  pid=$(cat "$gui_home/pid")
  [[ $pid =~ ^[0-9]+$ ]]
  # Traverse user-owned FUSE paths as their mount owner, without allow_other.
  executable=$(as_user approved readlink -f "/proc/$pid/exe")
  if [[ -n $expected_executable ]]; then [[ $executable == "$expected_executable" ]]; fi
  as_user approved test -x "${executable%/*}/libexec/legion-portable-control"
  if [[ $bundled_libraries == true ]]; then
    cat "/proc/$pid/maps" >"/home/approved/appimage-runtime-$label.txt"
    for library in libgtk-3.so.0 libglib-2.0.so.0 libpango-1.0.so.0; do
      grep -F "/usr/lib/legion_frontend/lib/$library" "/proc/$pid/maps"
    done
  fi
  gui_no_unit || fail 'Read-only startup launched a helper.'
  gui_click 90 228
  gui_wait_text 'Collect history' 1280x720+0+0 11
  gui_desktop xdotool mousemove --sync --window "$(head -n1 "$gui_home/window")" \
    1100 600 click --repeat 18 --delay 50 5
  gui_wait_text mode 260x25+359+648
  gui_click 734 667
  wait_until 30 gui_has_unit
  unit=$(gui_unit_query)
  [[ $unit =~ ^legion-portable-control-[0-9a-f-]+\.service$ ]]
  helper_pid=$(systemctl show --property=MainPID --value "$unit")
  [[ $helper_pid =~ ^[0-9]+$ && $helper_pid != 0 ]]
  gui_enabled() { nsenter --target "$helper_pid" --mount -- cat /tmp/legion-fixture/battery-conservation | grep -x enabled; }
  wait_until 15 gui_enabled
  echo 1 >"$conservation"
  gui_restore() {
    gui_click 1142 23
    gui_click 734 667
    nsenter --target "$helper_pid" --mount -- cat /tmp/legion-fixture/battery-conservation | grep -x disabled
  }
  wait_until 20 gui_restore
  echo 0 >"$conservation"
  echo "PASS: first-launch helper write/readback/restore from $label"
  gui_click 90 427
  gui_wait_text 'Hardware control' 1280x720+0+0 11
  gui_desktop bash -c 'source "$1"; desktop_ocr "$2" 11' bash \
    "$desktop_support/desktop_test_support.sh" "$gui_home/label.png" >"$gui_home/settings.txt"
  desktop_check_settings "$gui_home/settings.txt"
  # Xvfb may disconnect xdotool during close; the recorded app status wins.
  gui_click 1258 23 || true
  wait_until 15 test -s "$gui_home/exit"
  desktop_check_exit "$(cat "$gui_home/exit")" "$gui_log"
  desktop_verify_cleanup "$pid" "$helper_pid" "$unit"
  echo "PASS: close button exits normally and cleans up the helper from $label"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then desktop_main "$@"; fi
