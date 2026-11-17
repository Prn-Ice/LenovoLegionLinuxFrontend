#!/usr/bin/env bash
# Exercise capture with no sudo, service, or hardware operations.
set -euo pipefail
umask 077
source=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/check_graphics_tty.sh
root=$(mktemp -d -t legion-capture-test-XXXXXX)
trap 'rm -rf -- "$root"' EXIT
mkdir "$root/mock"
cat > "$root/mock/dispatch" <<'SH'
#!/usr/bin/env bash
set -eu
name=${0##*/}
printf '%s %s\n' "$name" "$*" >> "$TEST_CALLS"
case "$name" in
  tty) printf '%s\n' "${TEST_TTY:-/dev/tty3}" ;;
  sudo)
    [[ $1 != -v ]] || exit 0
    exec "$@"
    ;;
  systemctl)
    if [[ $1 == --user ]]; then
      shift
      case "$1" in
        show) echo "${TEST_AUDIO_STATE:-active}"; exit "${TEST_AUDIO_QUERY_RESULT:-0}" ;;
        stop) exit "${TEST_AUDIO_STOP_RESULT:-0}" ;;
        start) exit "${TEST_AUDIO_START_RESULT:-0}" ;;
        *) exit 99 ;;
      esac
    fi
    case "$1" in
      is-active) echo "${TEST_DISPLAY_STATE:-active}" ;;
      stop) exit "${TEST_STOP_RESULT:-0}" ;;
      start) exit "${TEST_START_RESULT:-0}" ;;
    esac
    ;;
  legion_cli)
    [[ "$*" == '--donotexpecthwmon graphics-mode status --json' ]] || exit 99
    echo '{"selected_mode":"hybrid","active_clients":[]}'
    exit "${TEST_STATUS_RESULT:-0}"
    ;;
  systemd-analyze) echo 'HibernateMode=shutdown' ;;
  sleep) ;;
  *) exit 99 ;;
esac
SH
chmod +x "$root/mock/dispatch"
for name in tty sudo systemctl legion_cli systemd-analyze sleep; do ln -s dispatch "$root/mock/$name"; done
# Only redirect the fixed production CLI to the local fake executable.
sed "s|CLI=/run/current-system/sw/bin/legion_cli|CLI=$root/mock/legion_cli|" "$source" > "$root/check.sh"
original_path=$PATH
index=0
no_match() {
  if grep -Eq -- "$1" "$2"; then
    printf 'Unexpected command: %s\n' "$1" >&2
    return 1
  fi
}
run_case() (
  local name=$1 expected=$2 restarted=$3 inspected=$4 answer=$5 result=0
  local units='pipewire.socket pipewire-pulse.socket pipewire.service wireplumber.service pipewire-pulse.service'
  shift 5
  export PATH="$root/mock:$original_path" XDG_STATE_HOME="$root/state-$index" TEST_CALLS="$root/calls-$index"
  for assignment in "$@"; do export "${assignment?}"; done
  timeout 5s bash "$root/check.sh" <<< "$answer" > "$root/output-$index" 2>&1 || result=$?
  if [[ $result != "$expected" ]]; then
    cat "$root/output-$index" >&2
    printf 'FAIL: %s: exit %s, expected %s\n' "$name" "$result" "$expected" >&2
    return 1
  fi
  if [[ $restarted == yes ]]; then grep -q 'systemctl start display-manager.service' "$TEST_CALLS";
  else no_match 'systemctl start display-manager.service' "$TEST_CALLS"; fi
  if [[ $inspected == yes ]]; then grep -q 'legion_cli --donotexpecthwmon graphics-mode status --json' "$TEST_CALLS";
  else no_match 'legion_cli --donotexpecthwmon graphics-mode status --json' "$TEST_CALLS"; fi
  no_match 'graphics-mode set' "$TEST_CALLS"
  sed 's/systemd-suspend-then-hibernate.service//g' "$TEST_CALLS" > "$root/without-sleep-unit-$index"
  no_match suspend "$root/without-sleep-unit-$index"
  if grep -q 'systemctl --user stop ' "$TEST_CALLS"; then
    grep -q "systemctl --user stop $units" "$TEST_CALLS"
    grep -q "systemctl --user start $units" "$TEST_CALLS"
    if [[ $restarted == yes ]]; then
      audio_line=$(grep -n '^systemctl --user start ' "$TEST_CALLS" | cut -d: -f1)
      display_line=$(grep -n '^systemctl start display-manager.service' "$TEST_CALLS" | cut -d: -f1)
      (( audio_line < display_line ))
    fi
  else
    no_match 'systemctl --user start ' "$TEST_CALLS"
  fi
  if [[ ${TEST_AUDIO_STATE:-} == inactive ]]; then no_match 'systemctl --user stop ' "$TEST_CALLS"; fi
  if [[ $inspected == yes ]]; then
    shopt -s nullglob
    logs=("$XDG_STATE_HOME"/legion-graphics-check/*.log)
    [[ ${#logs[@]} == 1 ]]
    grep -q '"selected_mode":"hybrid"' "${logs[0]}"
    (( (8#$(stat -c %a "${logs[0]}") & 077) == 0 ))
  fi
  printf 'PASS: %s\n' "$name"
)
for case_name in success cancel desktop status stop recovery inactive unexpected audio_inactive audio_query audio_transition audio_stop audio_restart; do
  index=$((index + 1))
  case "$case_name" in
    success) run_case success 0 yes yes y ;;
    cancel) run_case cancel 0 no no n ;;
    desktop) run_case 'desktop refused' 1 no no y TEST_TTY=/dev/pts/3 ;;
    status) run_case 'status failure recovers' 1 yes yes y TEST_STATUS_RESULT=1 ;;
    stop) run_case 'stop failure recovers' 1 yes no y TEST_STOP_RESULT=1 ;;
    recovery) run_case 'recovery failure reported' 1 yes yes y TEST_START_RESULT=1 ;;
    inactive) run_case 'already stopped preserved' 0 no yes y TEST_DISPLAY_STATE=inactive ;;
    unexpected) run_case 'unexpected state refused' 1 no no y TEST_DISPLAY_STATE=failed ;;
    audio_inactive) run_case 'audio already stopped' 0 yes yes y TEST_AUDIO_STATE=inactive ;;
    audio_query) run_case 'audio query failure recovers' 1 yes no y TEST_AUDIO_QUERY_RESULT=1 ;;
    audio_transition) run_case 'audio transitional state refused' 1 yes no y TEST_AUDIO_STATE=activating ;;
    audio_stop) run_case 'audio stop failure recovers' 1 yes no y TEST_AUDIO_STOP_RESULT=1 ;;
    audio_restart) run_case 'audio restart failure reported' 1 yes yes y TEST_AUDIO_START_RESULT=1 ;;
  esac
done
