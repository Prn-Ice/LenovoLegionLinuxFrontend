#!/usr/bin/env bash
# Hardware-free regressions for desktop readiness, failure gates and VM evidence.
# Functions passed through sourced helpers are intentional test boundaries.
# shellcheck disable=SC2016,SC2034,SC2329
set -euo pipefail
support=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=control/test/desktop_test_support.sh
source "$support/desktop_test_support.sh"
# shellcheck source=control/test/deb_evidence.sh
source "$support/deb_evidence.sh"
temporary=$(mktemp -d "${TMPDIR:-/tmp}/acceptance support.XXXXXXXX")
owned_child=
marker=acceptance-timeout-$$
finish_tests() {
  local status=$?
  trap - EXIT
  if [[ -n $owned_child && -r /proc/$owned_child/cmdline ]] && grep -qaF "$marker" "/proc/$owned_child/cmdline"; then
    kill -KILL "$owned_child" 2>/dev/null || true
  fi
  rm -rf -- "$temporary"
  exit "$status"
}
trap finish_tests EXIT
mkdir "$temporary/bin"
printf '#!/usr/bin/env bash\nprintf "99999\\n"\n' >"$temporary/bin/id"
printf '#!/usr/bin/env bash\necho forbidden >"$FORBIDDEN"\n' >"$temporary/bin/mount"
chmod +x "$temporary/bin/"*
expect_status 1 env PATH="$temporary/bin:$PATH" FORBIDDEN="$temporary/forbidden" \
  bash "$support/desktop_test_support.sh" /must/not/launch unused.log fixture >"$temporary/guard.log" 2>&1
test ! -e "$temporary/forbidden"
echo 'PASS: the desktop controller refuses fixture writes before its root/VM guard'

home=$temporary/fresh
desktop_prepare_home "$home"
[[ $(stat -c %a "$home/runtime") == 700 ]]
printf '%s\n' 'XDG_DOCUMENTS_DIR="$HOME"' | diff - "$home/config/user-dirs.dirs"
test ! -e "$home/preferences.hive"
[[ $(desktop_scale 11) == 100% && $(desktop_scale 7) == 300% ]]
cat >"$temporary/bin/tesseract" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$OMP_THREAD_LIMIT" "$@"
EOF
chmod +x "$temporary/bin/tesseract"
PATH="$temporary/bin:$PATH" desktop_ocr "$temporary/frame with spaces.png" 11 >"$temporary/ocr.txt"
printf '%s\n' 1 "$temporary/frame with spaces.png" stdout --psm 11 | diff - "$temporary/ocr.txt"
echo 'PASS: fresh Documents/runtime storage and single-thread OCR preserve arguments'

# GNU timeout owns the command's process group, including its blocked child.
expect_status 124 timeout --kill-after=2 1 bash -c '
  bash -c '\''sleep 60 & wait "$!"'\'' bash "$1" &
  child=$!; printf "%s\n" "$child" >"$2"; wait "$child"
' bash "$marker" "$temporary/child.pid"
owned_child=$(cat "$temporary/child.pid")
[[ $owned_child =~ ^[0-9]+$ ]]
state=$(awk '{print $3}' "/proc/$owned_child/stat" 2>/dev/null || true)
[[ -z $state || $state == Z ]] || fail 'A timed-out OCR command left its child running.'
echo 'PASS: timeout stops the owned child instead of leaving background work'

printf '123\n' >"$home/window"
(
  gui_home=$home
  gui_wait_text() { printf '%s\n' "$1" >>"$temporary/readiness"; }
  gui_desktop() { printf '%s\n' "$*" >>"$temporary/readiness"; }
  desktop_wait_ready
)
printf '%s\n' Dashboard 'xdotool windowfocus --sync 123' 'Battery health' | diff - "$temporary/readiness"
echo 'PASS: window activation precedes real content readiness and navigation'

printf 'Hardware control\nAdministrator access\n' >"$temporary/settings"
desktop_check_settings "$temporary/settings"
for obsolete in 'Installed service' 'Use on next launch' 'In use now:'; do
  printf '%s\n' "$obsolete" >"$temporary/settings"
  expect_status 1 bash -c 'source "$1"; desktop_check_settings "$2"' bash \
    "$support/desktop_test_support.sh" "$temporary/settings" >"$temporary/expected-error" 2>&1
done
printf 'normal startup\n' >"$temporary/app.log"
desktop_check_exit 0 "$temporary/app.log"
expect_status 1 bash -c 'source "$1"; desktop_check_exit 139 "$2"' bash \
  "$support/desktop_test_support.sh" "$temporary/app.log" >"$temporary/expected-error" 2>&1
for critical in Pango-CRITICAL GLib-CRITICAL GLib-GObject-CRITICAL; do
  printf '%s\n' "$critical" >"$temporary/app.log"
  expect_status 1 bash -c 'source "$1"; desktop_check_exit 0 "$2"' bash \
    "$support/desktop_test_support.sh" "$temporary/app.log" >"$temporary/expected-error" 2>&1
done
echo 'PASS: obsolete choices, nonzero window exits and runtime criticals remain failures'

expect_status 1 bash -c '
  source "$1"
  assert_gone() { :; }
  wait_until() { [[ $* != *"Legion control cleanup complete."* ]]; }
  gui_no_unit() { :; }
  assert_cleanup_succeeded() { :; }
  desktop_verify_cleanup 123 456 legion-portable-control-fixture.service
' bash "$support/desktop_test_support.sh"
expect_status 23 bash -c '
  source "$1"
  gui_home=$2; gui_wrapper=
  desktop_collect_diagnostics() { return 7; }
  trap desktop_finish EXIT
  exit 23
' bash "$support/desktop_test_support.sh" "$home"
echo 'PASS: missing helper cleanup fails and diagnostic errors preserve the first failure'

(
  gui_home=$home
  gui_log=$temporary/app.log
  gui_diagnostics=$temporary/diagnostics.txt
  touch "$home/display.log" "$home/exit"
  ps() { :; }
  journalctl() { :; }
  desktop_ocr() { :; }
  gui_desktop() {
    case "$*" in
      'xdotool getwindowfocus') echo 123 ;;
      'xdotool getmouselocation --shell') printf 'X=90\nY=228\nWINDOW=0\n' ;;
      *) return 1 ;;
    esac
  }
  desktop_collect_diagnostics >/dev/null 2>&1
  grep -Fxq 123 "$gui_diagnostics"
  grep -Fxq X=90 "$gui_diagnostics"
  grep -Fxq WINDOW=0 "$gui_diagnostics"
)
echo 'PASS: failure diagnostics retain the focus ID separately from pointer coordinates'

partial=$temporary/partial
complete=$temporary/complete
mkdir "$partial" "$complete"
for name in deb-gui.log 'desktop-frame-Debian package.png' 'desktop-diagnostics-Debian package.txt'; do
  printf 'synthetic failure evidence\n' >"$partial/$name"
done
expect_status 23 retain_deb_evidence "$partial" "$temporary/partial.tar.gz" 23
printf '%s\n' deb-gui.log 'desktop-frame-Debian package.png' 'desktop-diagnostics-Debian package.txt' | sort >"$temporary/expected"
tar -tzf "$temporary/partial.tar.gz" | sort | diff "$temporary/expected" -
for name in deb-versions.txt deb-gui.log deb-release-manifest.json deb-os-release deb-checks.json; do
  printf 'synthetic release evidence\n' >"$complete/$name"
done
retain_deb_evidence "$complete" "$temporary/complete.tar.gz" 0
printf '%s\n' deb-versions.txt deb-gui.log deb-release-manifest.json deb-os-release deb-checks.json | sort >"$temporary/expected"
tar -tzf "$temporary/complete.tar.gz" | sort | diff "$temporary/expected" -
(
  timeout() { return 33; }
  expect_status 23 retain_deb_evidence "$partial" "$temporary/unused.tar.gz" 23
  expect_status 33 retain_deb_evidence "$complete" "$temporary/unused.tar.gz" 0
)
echo 'PASS: Debian partial/full evidence and archive-error results retain their contracts'
