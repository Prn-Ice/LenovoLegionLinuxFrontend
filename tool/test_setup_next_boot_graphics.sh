#!/usr/bin/env bash
# Exercise setup without sudo, Nix builds, or profile changes.
set -euo pipefail
umask 077
script=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/setup_next_boot_graphics.sh
root=$(mktemp -d -t legion-setup-test-XXXXXX)
trap 'rm -rf -- "$root"' EXIT
mkdir "$root/mock"
cat > "$root/mock/dispatch" <<'SH'
#!/usr/bin/env bash
set -eu
name=${0##*/}
printf '%s %s\n' "$name" "$*" >> "$TEST_CALLS"
case "$name" in
  tty) echo "${TEST_TTY:-/dev/pts/3}" ;;
  systemd-inhibit)
    while [[ $1 != bash ]]; do shift; done
    exec "$@"
    ;;
  nix)
    case "$1" in
      eval)
        case "${!#}" in
          *.nextBootGraphics) echo "${TEST_ENABLED:-true}" ;;
          *.tags) echo "${TEST_TAGS:-[]}" ;;
          *) exit 99 ;;
        esac
        ;;
      build)
        [[ ${TEST_BUILD_FAIL:-0} == 0 ]] || exit 1
        echo "$TEST_BUILT"
        ;;
      *) exit 99 ;;
    esac
    ;;
  sudo)
    case "$1" in
      -v) exit 0 ;;
      test)
        [[ "$*" == 'test ! -e /var/lib/legion-graphics-boot/request.json' ]] || exit 99
        [[ ${TEST_PENDING:-0} == 0 ]]
        ;;
      nixos-rebuild) exec "$@" ;;
      *) exit 99 ;;
    esac
    ;;
  nixos-rebuild)
    [[ $1 == boot ]] || exit 99
    [[ ${TEST_INSTALL_FAIL:-0} == 0 ]] || exit 1
    : > "$TEST_INSTALLED"
    ;;
  readlink)
    case "${!#}" in
      /run/current-system)
        if [[ -e $TEST_INSTALLED && ${TEST_RUNTIME_CHANGED:-0} == 1 ]]; then
          echo /nix/store/unexpected-nixos-system-nixos
        else
          echo /nix/store/original-nixos-system-nixos
        fi
        ;;
      /nix/var/nix/profiles/system) echo "${TEST_PROFILE:-$TEST_BUILT}" ;;
      *) exit 99 ;;
    esac
    ;;
  cat)
    [[ $1 == /proc/sys/kernel/random/boot_id ]] || exit 99
    echo 11111111-1111-4111-8111-111111111111
    ;;
  *) exit 99 ;;
esac
SH
chmod +x "$root/mock/dispatch"
for name in tty systemd-inhibit nix sudo nixos-rebuild readlink cat; do ln -s dispatch "$root/mock/$name"; done
original_path=$PATH
index=0
no_match() {
  if grep -Eq -- "$1" "$2"; then
    printf 'Unexpected command: %s\n' "$1" >&2
    return 1
  fi
}
run_case() (
  local name=$1 expected=$2 installs=$3 answer=$4 result=0
  shift 4
  export PATH="$root/mock:$original_path" XDG_STATE_HOME="$root/state-$index"
  export TEST_CALLS="$root/calls-$index" TEST_INSTALLED="$root/installed-$index"
  export TEST_BUILT=/nix/store/reviewed-nixos-system-nixos
  for assignment in "$@"; do export "${assignment?}"; done
  timeout 5s bash "$script" <<< "$answer" > "$root/output-$index" 2>&1 || result=$?
  if [[ $result != "$expected" ]]; then
    "$REAL_CAT" "$root/output-$index" >&2
    printf 'FAIL: %s: exit %s, expected %s\n' "$name" "$result" "$expected" >&2
    return 1
  fi
  if [[ $installs == yes ]]; then
    grep -q 'nixos-rebuild boot ' "$TEST_CALLS"
    grep -q '?rev=384070f2ec75d95bee958f0f33545b5ecd73a23b#nixos' "$TEST_CALLS"
    grep -q -- --no-write-lock-file "$TEST_CALLS"
    grep -q -- '--what=sleep:shutdown --mode=block' "$TEST_CALLS"
  else
    no_match 'nixos-rebuild boot ' "$TEST_CALLS"
  fi
  no_match 'nixos-rebuild switch|graphics-mode set|systemctl reboot' "$TEST_CALLS"
  if [[ $name != 'nonterminal refused' ]]; then
    shopt -s nullglob
    logs=("$XDG_STATE_HOME"/legion-graphics-setup/*.log)
    [[ ${#logs[@]} == 1 ]]
    grep -q 'Log saved:' "${logs[0]}"
    (( (8#$(stat -c %a "${logs[0]}") & 077) == 0 ))
  fi
  printf 'PASS: %s\n' "$name"
)
REAL_CAT=$(command -v cat)
for case_name in success cancel nonterminal disabled specialisation build pending installation profile runtime; do
  # Each subshell gets a fresh fixture; exported controls cannot leak between cases.
  index=$((index + 1))
  case "$case_name" in
    success) run_case success 0 yes y ;;
    cancel) run_case cancel 0 no n ;;
    nonterminal) run_case 'nonterminal refused' 1 no y 'TEST_TTY=not a tty' ;;
    disabled) run_case 'disabled configuration refused' 1 no y TEST_ENABLED=false ;;
    specialisation) run_case 'specialisation refused' 1 no y 'TEST_TAGS=["no-nvidia"]' ;;
    build) run_case 'build failure' 1 no y TEST_BUILD_FAIL=1 ;;
    pending) run_case 'request state needs review' 1 no y TEST_PENDING=1 ;;
    installation) run_case 'installation failure' 1 yes y TEST_INSTALL_FAIL=1 ;;
    profile) run_case 'unexpected profile' 1 yes y TEST_PROFILE=/nix/store/other ;;
    runtime) run_case 'unexpected runtime change' 1 yes y TEST_RUNTIME_CHANGED=1 ;;
  esac
done
