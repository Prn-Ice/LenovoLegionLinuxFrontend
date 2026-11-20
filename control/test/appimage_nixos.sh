#!/usr/bin/env bash
# Exercise the real packaged GUI through NixOS's official appimage-run.
# Guest shell commands and jq expressions expand in their own processes.
# shellcheck disable=SC2016
set -euo pipefail
support=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=control/test/desktop_test_support.sh
source "$support/desktop_test_support.sh"
if [[ ${1:-} == --x11 ]]; then
  assert_vm_marker
  [[ $(id -u) != 0 ]] || fail 'The app must run as the unprivileged fixture user.'
  exec xvfb-run -a -s '-screen 0 1280x900x24' dbus-run-session -- bash -c '
    export LIBGL_ALWAYS_SOFTWARE=1 GSETTINGS_BACKEND=memory GDK_BACKEND=x11
    printf "%s" "$DISPLAY" >/home/approved/display
    printf "%s" "$XAUTHORITY" >/home/approved/authority
    appimage-run "$1" >>/home/approved/gui.log 2>&1 &
    app=$!
    trap '\''kill "$app" 2>/dev/null || true'\'' EXIT
    xdotool search --sync --onlyvisible --class io.github.prnice.legion_linux_frontend >/home/approved/window.id
    xdotool windowsize "$(head -n1 /home/approved/window.id)" 1280 720
    xdotool getwindowpid "$(head -n1 /home/approved/window.id)" >/home/approved/app.pid
    status=0; wait "$app" || status=$?
    printf "%s" "$status" >/home/approved/app.exit
    exit "$status"
  ' bash "$2"
fi
assert_disposable_vm
source_image=$1 fixtures=$2
# Failure diagnostics must not inherit an individual command's redirection.
exec 3>&2
image='/home/approved/AppImage with spaces/Legion.AppImage'
install -d -o approved -g users '/home/approved/AppImage with spaces'
install -o approved -g users -m755 "$source_image" "$image"
install -d -o approved -g users /home/approved/wayland-diagnostics /home/approved/gui-evidence
for log in gui.log wayland.log wayland-launcher.log sway.log; do
  install -o approved -g users -m644 /dev/null "/home/approved/$log"
done
desktop() {
  as_user approved env "DISPLAY=$(cat /home/approved/display)" \
    "XAUTHORITY=$(cat /home/approved/authority)" "$@"
}
click() { desktop xdotool mousemove --sync --window "$(head -n1 /home/approved/window.id)" "$1" "$2" click 1; }
screenshot() { desktop magick import -window root "/home/approved/gui-evidence/$1.png"; }
wayland() {
  as_user approved env XDG_RUNTIME_DIR=/run/user/1000 SWAYSOCK=/run/user/1000/sway.sock \
    WAYLAND_DISPLAY=wayland-1 GDK_BACKEND=wayland LIBGL_ALWAYS_SOFTWARE=1 GSETTINGS_BACKEND=memory "$@"
}
finish() {
  local status=$?
  trap - EXIT
  if ((status != 0)); then
    printf 'AppImage GUI test failed with status %s.\n' "$status" >&2
    screenshot privileged-control-failure || true
    screenshot missing-ui-label || true
    cat /home/approved/{gui,display,wayland,wayland-launcher,sway}.log >&2 || true
    for file in /home/approved/wayland-diagnostics/*-window.txt; do
      [[ ! -f $file ]] || cat "$file" >&2
    done
    local latest
    latest=$(find /home/approved/wayland-diagnostics -name '*-ocr.txt' | sort -V | tail -n1)
    if [[ -n $latest ]]; then
      cat "$latest" >&2
      magick identify "${latest%-ocr.txt}-frame.png" "${latest%-ocr.txt}-header.png" >&2 || true
    fi
    journalctl -b --no-pager -u 'legion-portable-control-*' >&2 || true
    journalctl -b --no-pager -k | tail -n100 >&2 || true
  fi
  if [[ -S /run/user/1000/sway.sock ]]; then wayland swaymsg exit || true; fi
  exit "$status"
} >&3
trap finish EXIT
trap 'printf "Failed GUI command: %s\n" "$BASH_COMMAND" >&3' ERR
wait_until 30 systemctl is-active polkit.service
echo 'Checking fixed-location read discovery inside the official runner'
as_user approved env "APPIMAGE_DEBUG_EXEC=$fixtures/bin/host-cli-read-test" appimage-run "$image" >/tmp/read-discovery.out
expected_cli=$(readlink -f /run/current-system/sw/bin/legion_cli)
grep -F "READ_CLI $expected_cli" /tmp/read-discovery.out
grep -Ex 'ok [0-9]+ /trusted-executable/read-cli' /tmp/read-discovery.out
# These kernel files are synthetic and exist only inside this VM.
conservation=/sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/conservation_mode
mount -t tmpfs tmpfs /sys/bus/platform/drivers
mkdir -p "$(dirname "$conservation")"
echo 0 >"$conservation"
echo success >/run/legion-gui-fixture-mode
echo allow >/run/legion-gui-approval
start_gui() {
  rm -f /home/approved/{app.pid,window.id,app.exit}
  gui_home=$(as_user approved mktemp -d /home/approved/legion-gui-XXXXXXXX)
  as_user approved bash -c 'source "$1"; desktop_prepare_home "$2"' bash "$support/desktop_test_support.sh" "$gui_home"
  test ! -e "$gui_home/preferences.hive"
  # Keep app settings fresh without extracting the same image for every close.
  as_user approved env "HOME=$gui_home" "XDG_CONFIG_HOME=$gui_home/config" \
    "XDG_DATA_HOME=$gui_home/data" XDG_CACHE_HOME=/home/approved/.cache "XDG_RUNTIME_DIR=$gui_home/runtime" \
    bash "$support/appimage_nixos.sh" --x11 "$image" >>/home/approved/display.log 2>&1 &
  wait_until 90 test -s /home/approved/app.pid
  pid=$(cat /home/approved/app.pid)
  [[ $pid =~ ^[0-9]+$ ]]
  desktop xdotool windowfocus --sync "$(head -n1 /home/approved/window.id)"
  wait_text 'Show CPU power usage' 1280x720+0+0 11
  desktop xdotool key Escape
}
close_gui() {
  # Xvfb may disconnect xdotool as it finishes the click. Check the app's status.
  click 1258 23 || true
  wait_until 15 test -s /home/approved/app.exit
  [[ $(cat /home/approved/app.exit) == 0 ]] || fail "Desktop exited with status $(cat /home/approved/app.exit) after close: $(cat /home/approved/gui.log)"
}
ocr() {
  desktop magick import -window root /home/approved/current.png &&
    desktop magick /home/approved/current.png -crop "$2" -resize "$(desktop_scale "${3:-7}")" /home/approved/label.png &&
    desktop timeout --kill-after=2 15 env OMP_THREAD_LIMIT=1 tesseract /home/approved/label.png stdout --psm "${3:-7}" 2>/dev/null | grep -Fi -- "$1"
}
wait_text() { wait_until 30 ocr "$@"; }
echo 'Checking fresh first-launch administrator access without a mode choice'
start_gui
wait_text Dashboard 380x32+288+7
wait_text 'Battery health' 1280x720+0+0 11
wait_until 10 test -f "$gui_home/preferences.hive"
icon=$(desktop xprop -id "$(head -n1 /home/approved/window.id)" _NET_WM_ICON)
[[ $icon != *'not found'* && $icon != *'no such atom'* ]]
echo 'Checking official appimage-run uses its bundled runtime on first launch'
[[ $(readlink "/proc/$pid/ns/user") != "$(readlink /proc/1/ns/user)" ]]
executable=$(as_user approved readlink "/proc/$pid/exe")
[[ $executable == */.cache/appimage-run/* ]]
helper=${executable%/*}/libexec/legion-portable-control
for library in libgtk-3.so.0 libglib-2.0.so.0 libpango-1.0.so.0; do
  grep -F "/usr/lib/legion_frontend/lib/$library" "/proc/$pid/maps"
done
echo 'Checking GUI denial, fresh approval on retry, and synthetic write/restore'
click 90 228
wait_text 'Collect history' 1280x720+0+0 11
desktop xdotool mousemove --window "$(head -n1 /home/approved/window.id)" 1100 600 click --repeat 18 --delay 50 5
wait_text mode 260x25+359+648
unit_query() { systemctl list-units --type=service --state=active --plain --no-legend 'legion-portable-control-*' | awk '{print $1}'; }
echo deny >/run/legion-gui-approval
click 734 667
wait_text 'Action could not be completed' 1280x720+0+0 11
[[ $(cat "$conservation") == 0 && -z $(unit_query) ]]
screenshot privileged-control-denied
echo allow >/run/legion-gui-approval
# The full-frame OCR image uses native pixels, so Close needs no scaling.
desktop timeout --kill-after=2 15 env OMP_THREAD_LIMIT=1 tesseract /home/approved/label.png stdout --psm 11 tsv 2>/dev/null >/tmp/close-words.tsv
awk -F '\t' 'tolower($NF) == "close" {print $7, $8, $9, $10}' /tmp/close-words.tsv >/tmp/close-coordinates
[[ $(wc -l </tmp/close-coordinates) == 1 ]] || fail "Expected one Close label: $(cat /tmp/close-words.tsv)"
read -r left top width height </tmp/close-coordinates
click "$((left + width / 2))" "$((top + height / 2))"
wait_text mode 260x25+359+648
click 734 667
has_unit() { [[ -n $(unit_query) ]]; }
wait_until 30 has_unit
unit=$(unit_query)
[[ $unit =~ ^legion-portable-control-[0-9a-f-]+\.service$ ]]
helper_pid=$(systemctl show --property=MainPID --value "$unit")
readback() { nsenter --target "$helper_pid" --mount -- cat /tmp/legion-fixture/battery-conservation; }
enabled() { readback | grep -x enabled; }
wait_until 15 enabled
reject grep -F .so "/proc/$helper_pid/maps"
grep -qx 1 "$conservation"
restore() { click 1142 23; click 734 667; readback | grep -x disabled; }
wait_until 20 restore
grep -qx 0 "$conservation"
[[ $(desktop xdotool getwindowpid "$(head -n1 /home/approved/window.id)") == "$pid" ]]
screenshot privileged-control-restored
click 90 427
wait_text 'Hardware control' 1280x720+0+0 11
desktop timeout --kill-after=2 15 env OMP_THREAD_LIMIT=1 tesseract /home/approved/label.png stdout --psm 11 2>/dev/null |
  tr '\n' ' ' | tr '[:upper:]' '[:lower:]' >/tmp/settings-labels
reject grep -E 'installed service|use on next launch|in use now:' /tmp/settings-labels
close_gui
assert_gone "$pid" 10
assert_gone "$helper_pid" 10
wait_until 10 bash -c 'journalctl -b --no-pager -u "$1" | grep -F "Legion control cleanup complete."' bash "${unit%.service}-cleanup.service"
assert_cleanup_succeeded
reject systemctl cat legion-control.service
reject systemctl cat legion-telemetry.service
# One functional first launch above plus ten repeats: eleven X11 closes total.
echo 'Checking ten more normal X11 closes through official appimage-run'
for ((attempt=1; attempt<=10; attempt++)); do
  start_gui
  wait_text Dashboard 380x32+288+7
  close_gui
done
reject grep -E 'Pango-CRITICAL|GLib-CRITICAL|GLib-GObject-CRITICAL' /home/approved/gui.log
echo 'Checking ten visible Wayland frames and native window closes'
install -d -o approved -g users -m700 /run/user/1000
printf '%s\n' 'output HEADLESS-1 resolution 1280x900' 'default_border none' >/home/approved/sway.conf
app_id=io.github.prnice.legion_linux_frontend
windows='[.. | objects | select(.app_id? == $app)]'
visible_window="$windows | select(length == 1) | .[0] | select(.visible == true and .rect.width > 0 and .rect.height > 0)"
no_window="$windows | length == 0"
wayland env WLR_BACKENDS=headless WLR_RENDERER=pixman dbus-run-session -- sway -c /home/approved/sway.conf >/home/approved/sway.log 2>&1 &
wait_until 45 test -S /run/user/1000/sway.sock
window_query() { wayland swaymsg -t get_tree | jq -e --arg app "$app_id" "$1" >/dev/null; }
wayland_frame() {
  # The crop checks the page heading, not the persistent navigation item.
  wayland bash -e -o pipefail -c '
    prefix=$1 number=$2 app_id=$3 visible_window=$4
    rm -f "$prefix"-{tree.json,window.json,window.txt,frame.png,header.png,ocr.txt}
    swaymsg -t get_tree >"$prefix-tree.json"
    node=$(jq -cer --arg app "$app_id" "$visible_window" "$prefix-tree.json")
    printf "%s\n" "$node" >"$prefix-window.json"
    geometry=$(jq -r '\''.rect | "\(.x),\(.y) \(.width)x\(.height)"'\'' <<<"$node")
    printf "attempt=%s launcher_pid=%s app_pid=%s geometry=%s visible=%s\n" "$number" "$(cat "$prefix-launcher.pid")" "$(jq -r .pid <<<"$node")" "$geometry" "$(jq -r .visible <<<"$node")" >"$prefix-window.txt"
    grim -g "$geometry" "$prefix-frame.png"
    magick "$prefix-frame.png" -crop 380x32+288+7 +repage -resize 300% "$prefix-header.png"
    timeout --kill-after=2 15 env OMP_THREAD_LIMIT=1 tesseract "$prefix-header.png" "$prefix-ocr" --psm 7 2>/dev/null
    grep -Fxi -- Dashboard "$prefix-ocr.txt"
  ' bash "$prefix" "$attempt" "$app_id" "$visible_window"
}
for ((attempt=1; attempt<=10; attempt++)); do
  prefix=/home/approved/wayland-diagnostics/attempt-$attempt
  rm -f /home/approved/wayland.exit
  wayland_home=$(as_user approved mktemp -d /home/approved/legion-wayland-XXXXXXXX)
  as_user approved bash -c 'source "$1"; desktop_prepare_home "$2"' bash "$support/desktop_test_support.sh" "$wayland_home"
  wayland env "HOME=$wayland_home" "XDG_CONFIG_HOME=$wayland_home/config" \
    "XDG_DATA_HOME=$wayland_home/data" XDG_CACHE_HOME=/home/approved/.cache dbus-run-session -- bash -c '
    appimage-run "$1" >>/home/approved/wayland.log 2>&1 &
    app=$!; printf "%s" "$app" >"$2-launcher.pid"
    status=0; wait "$app" || status=$?
    printf "%s" "$status" >/home/approved/wayland.exit
    exit "$status"
  ' bash "$image" "$prefix" >>/home/approved/wayland-launcher.log 2>&1 &
  wait_until 60 window_query "$visible_window"
  wait_until 30 wayland_frame
  cat "$prefix-window.txt"
  # Sway sends the native window-close request, not a process signal.
  wayland swaymsg "[app_id=\"$app_id\"] kill"
  wait_until 15 test -s /home/approved/wayland.exit
  [[ $(cat /home/approved/wayland.exit) == 0 ]] || fail "Wayland close failed: $(cat /home/approved/wayland.log)"
  wait_until 15 window_query "$no_window"
done
reject grep -E 'Pango-CRITICAL|GLib-CRITICAL|GLib-GObject-CRITICAL' /home/approved/wayland.log
# The compositor can close IPC before acknowledging exit. App closes were checked above.
wayland swaymsg exit || true
echo 'Checking the same helper rejects denied approval and a missing agent'
for user in denied challenge; do
  binary=/home/$user/helper
  install -o "$user" -g users -m755 "$helper" "$binary"
  status=0
  as_user "$user" timeout 15 "$binary" --control >/tmp/gui-denied.out 2>&1 || status=$?
  [[ $status != 0 && $status != 124 ]] || fail "Unexpected $user status $status: $(cat /tmp/gui-denied.out)"
  reject grep CONTROL_READY /tmp/gui-denied.out
done
