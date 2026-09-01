#!/usr/bin/env bash
set -euo pipefail

CLI="/run/current-system/sw/bin/legion_cli"
RUNTIME_SCRIPT="/run/legion-shutdown-diagnostics.sh"
RUNTIME_UNIT="/run/systemd/system/legion-shutdown-diagnostics.service"
RUNTIME_WANTS="/run/systemd/system/final.target.wants/legion-shutdown-diagnostics.service"
EVIDENCE_ROOT="/var/log/legion-shutdown-diagnostics"

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

capture_snapshot() {
  local output=$1
  local phase=$2

  # A missing diagnostic must not delay final.target or prevent poweroff.
  set +e
  export PATH="/run/current-system/sw/bin:/usr/bin:/bin"
  install -d -m 0750 "$output"

  {
    printf 'phase=%s\n' "$phase"
    printf 'captured_at=%s\n' "$(date --iso-8601=ns)"
    printf 'boot_id='
    cat /proc/sys/kernel/random/boot_id
    printf 'uptime='
    cat /proc/uptime
    uname -a
  } >"$output/summary.txt" 2>&1

  ps -eLo pid,tid,ppid,user,state,wchan:32,comm,args --sort=pid,tid \
    >"$output/processes.txt" 2>&1
  systemctl list-jobs --all --no-pager >"$output/systemd-jobs.txt" 2>&1
  systemctl --failed --no-pager >"$output/systemd-failed.txt" 2>&1

  for source in interrupts locks meminfo modules mounts swaps; do
    cp "/proc/$source" "$output/proc-$source.txt" 2>"$output/proc-$source.error"
  done

  {
    for task in /proc/[0-9]*/task/[0-9]*; do
      [[ -r "$task/status" ]] || continue
      state=
      while IFS=: read -r key value; do
        if [[ "$key" == "State" ]]; then
          state=$value
          break
        fi
      done <"$task/status"
      [[ "$state" == *'D (disk sleep)'* ]] || continue
      printf '\n=== %s state=%s ===\n' "$task" "$state"
      for field in comm wchan stack syscall status; do
        printf -- '--- %s ---\n' "$field"
        cat "$task/$field" 2>&1
      done
    done
  } >"$output/uninterruptible-tasks.txt" 2>&1

  {
    if command -v lspci >/dev/null; then
      lspci -nnk
      printf '\n=== NVIDIA display root port ===\n'
      lspci -vv -s 0000:00:01.1
    else
      printf 'lspci is unavailable; using raw PCI sysfs state.\n'
    fi
    for path in \
      /sys/bus/pci/devices/0000:00:01.1/power_state \
      /sys/bus/pci/devices/0000:00:01.1/power/runtime_status \
      /sys/bus/pci/devices/0000:00:01.1/power/control \
      /sys/bus/pci/devices/0000:00:01.1/current_link_speed \
      /sys/bus/pci/devices/0000:00:01.1/current_link_width \
      /sys/module/legion_laptop/drivers/platform:legion/*/gsync \
      /sys/module/legion_laptop/drivers/platform:legion/*/igpumode; do
      [[ -e "$path" ]] || continue
      printf '%s=' "$path"
      cat "$path"
    done
    printf '\n=== NVIDIA PCI functions still present ===\n'
    for device in /sys/bus/pci/devices/*; do
      [[ -r "$device/vendor" ]] || continue
      [[ $(<"$device/vendor") == "0x10de" ]] || continue
      printf '%s class=%s driver=%s\n' \
        "${device##*/}" \
        "$(<"$device/class")" \
      "$(readlink -f "$device/driver" 2>/dev/null || printf 'none')"
    done
  } >"$output/pci-and-graphics.txt" 2>&1
  return 0
}

if [[ ${1:-} == "--capture" ]]; then
  [[ $# -eq 3 ]] || fail "Internal capture mode requires an output path and phase."
  capture_snapshot "$2" "$3"
  exit 0
fi

tty_path=$(tty 2>/dev/null || true)
case "$tty_path" in
  /dev/tty[0-9]*) ;;
  *) fail "Run this script from a Linux virtual console such as Ctrl+Alt+F3, not $tty_path." ;;
esac

if [[ ${1:-} == "disarm" ]]; then
  sudo rm -f "$RUNTIME_WANTS" "$RUNTIME_UNIT" "$RUNTIME_SCRIPT"
  sudo systemctl daemon-reload
  printf 'Late shutdown diagnostics disarmed. Existing evidence was retained in %s.\n' "$EVIDENCE_ROOT"
  exit 0
fi

[[ $# -eq 1 ]] || fail "Usage: $0 baseline|detached|disarm"
case "$1" in
  baseline | detached) mode=$1 ;;
  *) fail "Usage: $0 baseline|detached|disarm" ;;
esac

[[ -x "$CLI" ]] || fail "Validated CLI is unavailable at $CLI."
[[ ! -e "$RUNTIME_UNIT" && ! -e "$RUNTIME_SCRIPT" && ! -e "$RUNTIME_WANTS" ]] ||
  fail "Shutdown diagnostics are already armed. Run '$0 disarm' before replacing them."

sudo -v
graphics_state=$(sudo "$CLI" --donotexpecthwmon graphics-mode status --json)
[[ "$graphics_state" == *'"reconciliation": "settled"'* ]] ||
  fail "Graphics topology must be settled before arming shutdown diagnostics."

if [[ "$mode" == "baseline" ]]; then
  [[ "$graphics_state" == *'"selected_mode": "hybrid"'* ]] ||
    fail "The baseline capture requires plain Hybrid policy."
  [[ "$graphics_state" == *'"effective_dgpu_state": "attached"'* ]] ||
    fail "The baseline capture requires an attached dGPU."
else
  [[ "$graphics_state" == *'"selected_mode": "hybrid-igpu-only"'* ]] ||
    fail "The detached capture requires Hybrid iGPU-only policy."
  [[ "$graphics_state" == *'"effective_dgpu_state": "detached"'* ]] ||
    fail "The detached capture requires a detached dGPU."
  [[ "$graphics_state" == *'"client_inspection_complete": true'* ]] ||
    fail "Root dGPU client inspection must be complete."
  [[ "$graphics_state" == *'"active_clients": []'* ]] ||
    fail "The detached capture requires zero active dGPU clients."
fi

started_at=$(date --iso-8601=seconds)
run_id=${started_at//:/-}
evidence_dir="$EVIDENCE_ROOT/$run_id-$mode"
script_path=$(readlink -f "${BASH_SOURCE[0]}")
bash_path=$(readlink -f "$BASH")
[[ -x "$bash_path" ]] || fail "Could not resolve the immutable Bash executable."

sudo install -d -m 0750 "$evidence_dir"
printf '%s\n' "$graphics_state" | sudo tee "$evidence_dir/graphics-status.json" >/dev/null
sudo "$script_path" --capture "$evidence_dir/pre-poweroff" pre-poweroff
sudo install -m 0755 "$script_path" "$RUNTIME_SCRIPT"

printf '%s\n' \
  '[Unit]' \
  'Description=Capture late shutdown process and PCI diagnostics' \
  'DefaultDependencies=no' \
  'After=shutdown.target umount.target' \
  'Before=final.target' \
  '' \
  '[Service]' \
  'Type=oneshot' \
  "ExecStart=$bash_path $RUNTIME_SCRIPT --capture $evidence_dir/final-target final-target" \
  'TimeoutStartSec=30s' \
  'StandardOutput=journal+console' \
  'StandardError=journal+console' |
  sudo install -D -m 0644 /dev/stdin "$RUNTIME_UNIT"
sudo install -d -m 0755 "${RUNTIME_WANTS%/*}"
sudo ln -s "../${RUNTIME_UNIT##*/}" "$RUNTIME_WANTS"
sudo systemctl daemon-reload

if ! sudo systemctl start "${RUNTIME_UNIT##*/}" ||
  ! sudo test -s "$evidence_dir/final-target/summary.txt"; then
  sudo rm -f "$RUNTIME_WANTS" "$RUNTIME_UNIT" "$RUNTIME_SCRIPT"
  sudo systemctl daemon-reload
  fail "The runtime final.target snapshot smoke test failed; diagnostics were disarmed."
fi
sudo rm -rf "$evidence_dir/final-target"

printf '\n============================================================\n'
printf 'DIAGNOSTICS ARMED. SHUTDOWN HAS NOT STARTED.\n'
printf '============================================================\n'
printf 'Shutdown diagnostics armed for the %s case.\n' "$mode"
printf 'Pre-poweroff evidence: %s/pre-poweroff\n' "$evidence_dir"
printf 'The late snapshot will be written to: %s/final-target\n' "$evidence_dir"
printf 'The exact runtime unit invocation passed a non-disruptive smoke test.\n'
printf 'This script did not change graphics policy and will not power off the system.\n'
printf '\nNEXT STEP: Film the TTY, then run exactly:\n'
printf '  sudo systemctl poweroff\n\n'
printf 'To cancel before poweroff, run: %s disarm\n' "$script_path"

sysrq_value=$(< /proc/sys/kernel/sysrq)
if [[ "$sysrq_value" != "1" ]]; then
  printf 'WARNING: kernel.sysrq=%s; blocked-task keys may be unavailable during a stall.\n' "$sysrq_value" >&2
fi
