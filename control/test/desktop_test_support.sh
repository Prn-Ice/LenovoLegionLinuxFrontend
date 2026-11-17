#!/usr/bin/env bash
# Launch a desktop, recognize its first frame, and use its real close button.
set -euo pipefail
# shellcheck source=control/test/portable_session_test.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/portable_session_test.sh"
[[ $(id -u) != 0 ]]
image=$1 log_path=$HOME/$2 label=$3 expected_executable=${4:-} bundled_libraries=${5:-false}
temporary=$(mktemp -d "$HOME/legion-gui-XXXXXXXX")
process=
stop_gui() {
  if [[ -n $process ]]; then
    kill -TERM -- "-$process" 2>/dev/null || true
    for ((attempt=0; attempt<50; attempt++)); do
      kill -0 -- "-$process" 2>/dev/null || break
      sleep 0.1
    done
    kill -KILL -- "-$process" 2>/dev/null || true
    wait "$process" 2>/dev/null || true
  fi
  rm -rf -- "$temporary"
}
trap stop_gui EXIT
env -u JAVA_HOME -u LD_LIBRARY_PATH GSETTINGS_BACKEND=memory GDK_BACKEND=x11 \
  LIBGL_ALWAYS_SOFTWARE=1 XDG_CONFIG_HOME="$temporary/config" XDG_DATA_HOME="$temporary/data" \
  setsid "$image" >"$log_path" 2>&1 &
process=$!
running() { [[ -r /proc/$process/stat ]] && [[ $(awk '{print $3}' "/proc/$process/stat") != Z ]]; }
started=$SECONDS
deadline=$((SECONDS + 120))
while true; do
  if windows=$(xdotool search --onlyvisible --class io.github.prnice.legion_linux_frontend) && running; then
    window=${windows%%$'\n'*}
    frame=$HOME/desktop-frame-$label.png
    import -window "$window" "$frame"
    convert "$frame" -crop 380x32+288+7 -resize 300% "$temporary/dashboard.png"
    text=$(tesseract "$temporary/dashboard.png" stdout --psm 7 2>/dev/null)
    if [[ ${text,,} == *dashboard* ]]; then break; fi
  fi
  if ! running || ((SECONDS >= deadline)); then
    cat "$log_path" >&2
    fail 'Desktop did not render a visible Dashboard before the deadline.'
  fi
  sleep 0.1
done
pid=$(xdotool getwindowpid "$window")
executable=$(readlink -f "/proc/$pid/exe")
if [[ -n $expected_executable ]]; then [[ $executable == "$expected_executable" ]]; fi
if [[ $bundled_libraries == true ]]; then
  maps=$HOME/appimage-runtime-$label.txt
  cat "/proc/$pid/maps" >"$maps"
  for library in libgtk-3.so.0 libglib-2.0.so.0 libpango-1.0.so.0; do
    grep -F "/usr/lib/legion_frontend/lib/$library" "$maps"
  done
fi
echo "PASS: visible Flutter window from $label after $((SECONDS - started))s"
geometry=$(xdotool getwindowgeometry --shell "$window")
width=$(sed -n 's/^WIDTH=//p' <<<"$geometry")
xdotool mousemove --window "$window" "$((width - 22))" 23 click 1
deadline=$((SECONDS + 15))
while running; do
  ((SECONDS < deadline)) || fail 'The close button did not stop the desktop within 15 seconds.'
  sleep 0.1
done
status=0
wait "$process" || status=$?
[[ $status == 0 ]] || { cat "$log_path" >&2; fail "Desktop exited with status $status"; }
reject grep -E 'Pango-CRITICAL|GLib-CRITICAL|GLib-GObject-CRITICAL' "$log_path"
echo "PASS: close button exits normally from $label"
