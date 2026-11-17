#!/usr/bin/env bash
# Fixed next-boot operations. Nix supplies executable paths, not callers.
set -euo pipefail
umask 077

STATE_DIR=/var/lib/legion-graphics-boot
BOOT_ID_PATH=/proc/sys/kernel/random/boot_id
DRM_ROOT=/sys/class/drm
ROOT_UID=0
CLI='@cli@'
LIFECYCLE='@lifecycle@'
MODPROBE='@modprobe@'
SYSTEMCTL='@systemctl@'
state='{"phase":"none"}'
consumed=0
temporary=
failure='Boot operation interrupted or command failed; queue hybrid for recovery'

fail() {
  failure=$1
  printf 'Boot graphics operation failed: %s\n' "$failure" >&2
  exit 1
}

write_state() {
  temporary=$(mktemp "$STATE_DIR/.request-XXXXXX") || return 1
  printf '%s\n' "$state" > "$temporary" || return 1
  # With a file operand and no -d/-f, GNU sync calls fsync, including on directories.
  sync -- "$temporary" || return 1
  mv -fT -- "$temporary" "$STATE_DIR/request.json" || return 1
  temporary=
  sync -- "$STATE_DIR" || return 1
}

# shellcheck disable=SC2329 # Invoked by the EXIT trap.
finish() {
  local result=$?
  trap - EXIT
  if [[ $consumed == 1 ]]; then
    state=$(jq -c --arg error "${failure:0:4096}" '. + {phase:"failed", error:$error}' <<< "$state")
    # A failed write leaves the durable applying record as the recovery barrier.
    write_state || result=1
  fi
  if [[ -n $temporary ]]; then rm -f -- "$temporary"; fi
  exit "$result"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

read_state() {
  local path="$STATE_DIR/request.json" size
  [[ -e $path || -L $path ]] || return 0
  [[ -f $path && ! -L $path ]] || fail 'Boot request must be a regular file'
  [[ $(stat -c %u "$path") == "$ROOT_UID" ]] || fail 'Boot request must be root-owned'
  (( (8#$(stat -c %a "$path") & 077) == 0 )) || fail 'Boot request must be private'
  size=$(stat -c %s "$path")
  (( size <= 65536 )) || fail 'Boot request exceeds size limit'
  state=$(head -c 65537 -- "$path" | jq -cse '
    def uuid: type == "string" and length == 36 and test("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$");
    if length != 1 then error("Expected one boot request") else .[0] end |
    if type != "object" then error("Invalid boot request") else . end |
    if (.phase != "pending" and .phase != "applying" and .phase != "failed" and .phase != "completed" and .phase != "cancelled")
      then error("Invalid boot request phase") else . end |
    if .phase == "cancelled" then .
    elif ((.mode == "hybrid" or .mode == "hybrid-igpu-only") and
          (.requested_boot_id | uuid) and
          (.requested_at | type == "number" and isfinite)) then .
    else error("Invalid boot request mode, UUID, or timestamp") end
  ') || fail 'Invalid boot request state; refusing graphics changes'
}

run_command() {
  local result=0
  # Match the old subprocess timeout: stop the command at 40s, without a grace period.
  output=$(timeout --signal=KILL 40s "$@") || result=$?
  if [[ -n $output ]]; then printf '%s\n' "$output" >&2; fi
  # systemctl returns nonzero while starting; only its state text is authoritative.
  if (( result != 0 )) && ! [[ $# == 2 && $1 == "$SYSTEMCTL" && $2 == is-system-running && $result -lt 124 ]]; then
    fail "$1 exited $result"
  fi
}

graphics_status() {
  run_command "$CLI" --donotexpecthwmon graphics-mode status --json
  status=$(jq -cse 'if length == 1 and (.[0] | type == "object" and .schema_version == 1) then .[0] else error("Invalid authoritative graphics status") end' <<< "$output") ||
    fail 'Invalid authoritative graphics status'
}

validate_clients() {
  jq -e '.client_inspection_complete == true and .active_clients == []' <<< "$status" > /dev/null ||
    fail 'NVIDIA clients are active or client inspection is incomplete'
}

check_internal_panel() {
  local path connector connected internal_connected=0
  for path in "$DRM_ROOT"/card*-*/status; do
    [[ -e $path ]] || continue
    connected=$(cat -- "$path")
    connector=${path%/status}
    if [[ $connected == connected ]]; then
      [[ ${connector##*/} == *-eDP-* ]] || fail 'Disconnect external displays before requesting iGPU-only'
      internal_connected=1
    fi
  done
  [[ $internal_connected == 1 ]] || fail 'A connected internal eDP panel is required for iGPU-only'
}

boot() {
  local phase pending=0 mode now expected
  phase=$(jq -r .phase <<< "$state")
  [[ $phase != failed && $phase != applying ]] ||
    fail 'Previous boot transition failed or was interrupted; queue hybrid for recovery'
  run_command "$SYSTEMCTL" is-system-running
  if [[ $output != starting ]]; then
    printf '%s\n' '{"phase":"deferred","reason":"Not in system startup; no hardware commands run"}'
    return
  fi
  if [[ $phase == pending ]]; then
    if [[ $(jq -r .requested_boot_id <<< "$state") == "$boot_id" ]]; then
      printf '%s\n' '{"phase":"deferred","reason":"Request belongs to this boot; reboot required"}'
      return
    fi
    pending=1
    mode=$(jq -r .mode <<< "$state")
    # Persist consumption before any hardware command; crashes must not retry.
    state=$(jq -c --arg boot "$boot_id" '. + {phase:"applying", attempted_boot_id:$boot}' <<< "$state")
    write_state
    consumed=1
    now=$(date +%s.%N)
    jq -e --argjson now "$now" '($now - .requested_at) as $age | $age >= 0 and $age <= 86400' <<< "$state" > /dev/null ||
      fail 'Boot request expired or the clock moved backwards; queue a fresh request'
    run_command "$SYSTEMCTL" list-units 'user@*.service' --state=active,activating --no-legend --plain
    [[ -z ${output//[[:space:]]/} ]] || fail 'A user manager is already running; refusing boot transition'
    graphics_status
    validate_clients
    jq -e '.selected_mode == "hybrid" or .selected_mode == "hybrid-igpu-only"' <<< "$status" > /dev/null ||
      fail 'Boot switching requires an existing Hybrid policy; restore Hybrid in BIOS first'
    jq -e --arg mode "$mode" '.available_modes | type == "array" and index($mode) != null' <<< "$status" > /dev/null ||
      fail 'Requested mode is not supported by this machine'
    if [[ $mode == hybrid-igpu-only ]]; then check_internal_panel; fi
    run_command "$CLI" --donotexpecthwmon graphics-mode set "$mode" --json
  fi
  run_command "$CLI" --donotexpecthwmon graphics-mode reconcile --json
  run_command "$LIFECYCLE" "$CLI" cleanup "$MODPROBE"
  if [[ $pending == 1 ]]; then
    graphics_status
    validate_clients
    expected=attached
    if [[ $mode == hybrid-igpu-only ]]; then expected=detached; fi
    jq -e --arg mode "$mode" --arg expected "$expected" '
      .selected_mode == $mode and .expected_dgpu_state == $expected and
      .effective_dgpu_state == $expected and .reconciliation == "settled"
    ' <<< "$status" > /dev/null || fail 'Requested graphics topology did not settle'
    state=$(jq -c --argjson status "$status" '. + {phase:"completed", final_status:$status}' <<< "$state")
    write_state
    consumed=0
  fi
  printf '%s\n' "$state"
}

[[ $EUID == "$ROOT_UID" ]] || fail 'Use the authorized LegionControl1 next-boot methods'
action=${1:-}
case "$action" in
  request) [[ $# == 2 && ( $2 == hybrid || $2 == hybrid-igpu-only ) ]] || fail 'Only hybrid and hybrid-igpu-only can be queued' ;;
  cancel|status|boot) [[ $# == 1 ]] || fail 'Invalid next-boot arguments' ;;
  *) fail 'Unknown next-boot operation' ;;
esac
if [[ ! -e $STATE_DIR ]]; then mkdir -m 700 -- "$STATE_DIR"; fi
[[ -d $STATE_DIR && ! -L $STATE_DIR && $(stat -c %u "$STATE_DIR") == "$ROOT_UID" ]] ||
  fail 'Boot request directory must be private and root-owned'
(( (8#$(stat -c %a "$STATE_DIR") & 077) == 0 )) || fail 'Boot request directory must be private and root-owned'
[[ ! -L $STATE_DIR/lock ]] || fail 'Boot request lock must not be a symlink'
exec 9>> "$STATE_DIR/lock"
flock --exclusive --nonblock 9 || fail 'Another boot graphics operation holds the lock'
boot_id=$(cat "$BOOT_ID_PATH")
[[ $boot_id =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || fail 'Invalid current boot UUID'
case "$action" in
  request)
    state=$(jq -cn --arg mode "$2" --arg boot "$boot_id" --argjson now "$(date +%s.%N)" \
      '{phase:"pending", mode:$mode, requested_boot_id:$boot, requested_at:$now}')
    write_state
    printf '%s\n' "$state"
    ;;
  cancel)
    read_state
    phase=$(jq -r .phase <<< "$state")
    [[ $phase != failed && $phase != applying ]] || fail 'A boot transition failed or was interrupted. Queue hybrid for recovery instead.'
    if [[ $phase == pending ]]; then state='{"phase":"cancelled"}'; write_state; fi
    printf '%s\n' "$state"
    ;;
  status) read_state; printf '%s\n' "$state" ;;
  boot) read_state; boot ;;
esac
