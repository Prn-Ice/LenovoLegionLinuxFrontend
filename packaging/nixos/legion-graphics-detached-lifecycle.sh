# shellcheck shell=bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  printf 'Usage: %s LEGION_CLI ACTION MODPROBE\n' "$0" >&2
  exit 64
fi

cli=$1
action=$2
modprobe=$3
sys_module_root=${LEGION_SYS_MODULE_ROOT:-/sys/module}
dev_root=${LEGION_DEV_ROOT:-/dev}

case "$action" in
  preflight | cleanup) ;;
  *)
    printf 'Unknown detached graphics lifecycle action: %s\n' "$action" >&2
    exit 64
    ;;
esac

inspect_graphics() {
  local cli_status graphics_state

  set +e
  graphics_state=$(
    "$cli" --donotexpecthwmon graphics-mode status --json
  )
  cli_status=$?
  set -e

  printf '%s\n' "$graphics_state" >&2
  if [[ $cli_status -ne 0 ]]; then
    printf 'Graphics status failed with CLI exit %d.\n' "$cli_status" >&2
    return 1
  fi

  jq --exit-status --raw-output '
    . as $status |
    if type != "object"
      or .schema_version != 1
      or (["settled", "blocked", "needed", "unknown"] | index($status.reconciliation)) == null
      or (["attached", "detached", "partial", "unknown"] | index($status.effective_dgpu_state)) == null
      or (["attached", "detached"] | index($status.expected_dgpu_state)) == null
      or (.client_inspection_complete | type) != "boolean"
      or (.active_clients | type) != "array"
    then error("invalid graphics status response")
    elif .expected_dgpu_state == "attached" then "attached-policy"
    elif (.active_clients | length) > 0 then "clients"
    elif .effective_dgpu_state == "detached"
      and .reconciliation == "settled"
      and .client_inspection_complete
    then "detached-safe"
    else "unsafe"
    end
  ' <<<"$graphics_state"
}

if ! outcome=$(inspect_graphics); then
  printf 'Could not validate graphics state for %s.\n' "$action" >&2
  exit 1
fi

case "$outcome" in
  attached-policy)
    exit 0
    ;;
  clients)
    printf 'Detached graphics %s blocked because dGPU clients are active.\n' "$action" >&2
    exit 2
    ;;
  unsafe)
    printf 'Detached graphics %s requires settled topology and complete zero-client inspection.\n' \
      "$action" >&2
    exit 2
    ;;
  detached-safe) ;;
  *)
    printf 'Graphics status produced an unknown lifecycle outcome.\n' >&2
    exit 1
    ;;
esac

[[ "$action" == "cleanup" ]] || exit 0

modules=(nvidia_drm nvidia_uvm nvidia_modeset nvidia)
loaded_modules=()
for module in "${modules[@]}"; do
  if [[ -d "$sys_module_root/$module" ]]; then
    loaded_modules+=("$module")
  fi
done

if (( ${#loaded_modules[@]} > 0 )); then
  if ! "$modprobe" --remove "${loaded_modules[@]}"; then
    printf 'Could not unload the unused NVIDIA module stack.\n' >&2
    exit 1
  fi
fi

for module in "${modules[@]}"; do
  if [[ -d "$sys_module_root/$module" ]]; then
    printf 'NVIDIA module remains loaded after cleanup: %s\n' "$module" >&2
    exit 1
  fi
done

shopt -s nullglob
device_nodes=(
  "$dev_root"/nvidia[0-9]*
  "$dev_root"/nvidiactl
  "$dev_root"/nvidia-modeset
  "$dev_root"/nvidia-uvm
  "$dev_root"/nvidia-uvm-tools
  "$dev_root"/nvidia-caps/nvidia-cap*
)
if (( ${#device_nodes[@]} > 0 )); then
  rm -f -- "${device_nodes[@]}"
fi
if [[ -d "$dev_root/nvidia-caps" ]]; then
  rmdir --ignore-fail-on-non-empty "$dev_root/nvidia-caps"
fi

if ! final_outcome=$(inspect_graphics); then
  printf 'Could not verify graphics state after NVIDIA cleanup.\n' >&2
  exit 1
fi
if [[ "$final_outcome" != "detached-safe" ]]; then
  printf 'Graphics state changed during NVIDIA cleanup: %s\n' "$final_outcome" >&2
  exit 1
fi
