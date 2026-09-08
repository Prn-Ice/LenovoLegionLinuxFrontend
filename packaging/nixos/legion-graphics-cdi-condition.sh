# shellcheck shell=bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'Usage: %s LEGION_CLI\n' "$0" >&2
  exit 64
fi

sys_pci_root=${LEGION_SYS_PCI_ROOT:-/sys/bus/pci/devices}
nvidia_present=false
for vendor in "$sys_pci_root"/*/vendor; do
  if [[ -r "$vendor" ]] && [[ "$(<"$vendor")" == "0x10de" ]]; then
    nvidia_present=true
    break
  fi
done
[[ "$nvidia_present" == true ]] || exit 1

# Resume can temporarily re-enumerate NVIDIA while detached policy is selected.
# Do not let CDI generation open it before graphics reconciliation can detach it.
if ! graphics_state=$("$1" --donotexpecthwmon graphics-mode status --json); then
  printf 'Skipping NVIDIA CDI generation: graphics policy is unavailable.\n' >&2
  exit 1
fi

if ! jq --exit-status --slurp '
  length == 1 and (.[0] |
    type == "object" and .schema_version == 1 and .expected_dgpu_state == "attached"
  )
' <<<"$graphics_state" >/dev/null; then
  printf 'Skipping NVIDIA CDI generation: graphics policy does not permit attached NVIDIA.\n' >&2
  exit 1
fi
