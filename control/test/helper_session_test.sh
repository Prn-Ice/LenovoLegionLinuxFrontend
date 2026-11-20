#!/usr/bin/env bash
# Shared commands for tests running inside a disposable VM.
# Commands passed to guest shells expand there; namerefs address session maps.
# shellcheck disable=SC2016,SC2154,SC2178

fail() { printf '%s\n' "$*" >&2; exit 1; }

expect_status() {
  local expected=$1 status=0
  shift
  "$@" || status=$?
  [[ $status == "$expected" ]] || fail "Expected status $expected, got $status: $*"
}

reject() {
  local status=0
  "$@" || status=$?
  [[ $status != 0 ]] || fail "Command unexpectedly succeeded: $*"
}

wait_until() {
  local seconds=$1 deadline
  shift
  deadline=$((SECONDS + seconds))
  until "$@"; do
    if ((SECONDS >= deadline)); then
      journalctl -b --no-pager -n 60 >&2 || true
      printf 'Timed out after %s seconds: %s\n' "$seconds" "$*" >&2
      return 1
    fi
    sleep 0.1
  done
}

as_user() {
  local user=$1
  shift
  # Keep an ordinary-user parent alive, as the original shell-driven app did.
  runuser -u "$user" -- bash -c '"$@"; status=$?; exit "$status"' bash "$@"
}

assert_cleanup_succeeded() {
  journalctl -b --no-pager > /tmp/legion-cleanup-journal
  reject grep -E 'legion-(bootstrap-probe|control-helper)-\S+-cleanup\.service.*([Ff]ailed|203/EXEC)' /tmp/legion-cleanup-journal
}

wait_collected() {
  local pattern=${1:-legion-control-helper-*} seconds=${2:-15}
  wait_until "$seconds" bash -c 'test -z "$(systemctl list-units --all --plain --no-legend "$1")"' bash "$pattern"
}

session_new() {
  local name=$1 user=$2 launcher=$3 copy=${4:-true} directory binary ready cli
  declare -gA "$name"
  local -n ref=$name
  ref[user]=$user
  directory=$(as_user "$user" mktemp -d "/home/$user/Portable app.XXXXXX")
  ref[output]=$directory/client.out
  ref[input]=$directory/client.in
  binary=$launcher
  if [[ $copy == true ]]; then
    binary=$directory/helper-bootstrap-probe
    as_user "$user" cp "$launcher" "$binary"
    as_user "$user" chmod 700 "$binary"
  fi
  as_user "$user" mkfifo "${ref[input]}"
  as_user "$user" bash -c 'input=$1; shift; exec legion-helper-test-client "$@" <>"$input"' bash "${ref[input]}" "$binary" "${@:5}" >"${ref[output]}" 2>"${ref[output]}.err" &
  if ! wait_until 20 grep CLIENT_READY "${ref[output]}"; then
    cat "${ref[output]}" "${ref[output]}.err" >&2
    return 1
  fi
  ready=$(cat "${ref[output]}")
  [[ $ready =~ CLIENT_READY\ client=([0-9]+)\ helper=([0-9]+)\ unit=([^[:space:]]+)\ address=([^[:space:]]+) ]] || fail "$ready"
  ref[client]=${BASH_REMATCH[1]}
  ref[helper]=${BASH_REMATCH[2]}
  ref[unit]=${BASH_REMATCH[3]}
  ref[address]=${BASH_REMATCH[4]}
  ref[cli]=
  if [[ $ready =~ \ cli=([^[:space:]]+) ]]; then
    cli=${BASH_REMATCH[1]}
    printf -v 'ref[cli]' '%b' "${cli//%/\\x}"
  fi
  [[ $ready =~ \ bus=([^[:space:]]+) ]] || fail "$ready"
  ref[bus_name]=${BASH_REMATCH[1]}
  ref[runtime]=/run/${ref[unit]%.service}
}

session_begin() {
  local -n ref=$1
  ref[previous]=$(wc -l <"${ref[output]}")
  as_user "${ref[user]}" bash -c 'printf "%s\n" "$1" >"$2"' bash "$2" "${ref[input]}"
}

session_expect() {
  local -n ref=$1
  local expected="PASS $2"
  if [[ -n ${3:-} ]]; then expected="ERROR $2 $3"; fi
  if ! wait_until 15 bash -c 'tail -n +"$1" "$2" | grep -F -- "$3"' bash "$((ref[previous] + 1))" "${ref[output]}" "$expected"; then
    cat "${ref[output]}" "${ref[output]}.err" >&2
    return 1
  fi
}

session_send() { session_begin "$1" "$2"; session_expect "$1" "$2" "${3:-}"; }

session_private() {
  local -n ref=$1
  shift
  nsenter --target "${ref[helper]}" --mount -- "$@"
}

session_prepare() {
  session_private "$1" bash -c 'mkdir -p /tmp/legion-fixture; rm -f /tmp/legion-fixture/ready /tmp/legion-fixture/pids; printf "%s\n" "$1" > /tmp/legion-fixture/mode' bash "$2"
}

session_value() { session_private "$1" cat "/tmp/legion-fixture/$2"; }

session_wait_tree() {
  local -n ref=$1
  wait_until 10 session_private "$1" test -f /tmp/legion-fixture/ready
  ref[pids]=$(session_value "$1" pids)
  local -a tree_pids
  read -r -a tree_pids <<<"${ref[pids]//$'\n'/ }"
  [[ ${#tree_pids[@]} == 3 ]] || fail "Expected three backend processes: ${ref[pids]}"
}

assert_gone() {
  local pid
  for pid in $1; do
    [[ $pid =~ ^[0-9]+$ ]] || fail "Invalid process ID: $pid"
    wait_until "${2:-15}" test ! -e "/proc/$pid"
  done
}

session_close() {
  local -n ref=$1
  session_begin "$1" close
  wait_until 8 grep CLIENT_CLOSED "${ref[output]}"
  wait_until 8 test ! -e "${ref[runtime]}"
  wait_until 8 bash -c 'journalctl -b --no-pager -u "$1" | grep -F "Legion control cleanup complete."' bash "${ref[unit]%.service}-cleanup.service"
}
