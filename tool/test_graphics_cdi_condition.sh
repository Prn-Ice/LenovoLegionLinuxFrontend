#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
CONDITION=${1:-"$SCRIPT_DIR/../packaging/nixos/legion-graphics-cdi-condition.sh"}
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
export LEGION_SYS_PCI_ROOT="$TMP_DIR/pci"
mkdir -p "$LEGION_SYS_PCI_ROOT/0000:01:00.0"
printf '0x10de\n' >"$LEGION_SYS_PCI_ROOT/0000:01:00.0/vendor"

cat >"$TMP_DIR/legion_cli" <<'EOF'
#!/usr/bin/env bash
[[ "$*" == '--donotexpecthwmon graphics-mode status --json' ]] || exit 64
printf '%s\n' "$GRAPHICS_JSON"
exit "${GRAPHICS_EXIT:-0}"
EOF
chmod +x "$TMP_DIR/legion_cli"

assert_condition() {
  local expected=$1 actual=0
  bash "$CONDITION" "$TMP_DIR/legion_cli" >"$TMP_DIR/stdout" 2>"$TMP_DIR/stderr" || actual=$?
  if [[ $actual -ne $expected ]]; then
    printf 'Expected CDI condition exit %d, got %d for %s.\n' "$expected" "$actual" "$GRAPHICS_JSON" >&2
    cat "$TMP_DIR/stderr" >&2
    exit 1
  fi
}

# Resume temporarily reattaches NVIDIA, but detached policy must still skip CDI.
export GRAPHICS_JSON='{"active_clients":[],"client_inspection_complete":false,"effective_dgpu_state":"attached","expected_dgpu_state":"detached","reconciliation":"blocked","schema_version":1,"selected_mode":"hybrid-igpu-only"}'
assert_condition 1

attached='{"active_clients":[],"client_inspection_complete":true,"effective_dgpu_state":"attached","expected_dgpu_state":"attached","reconciliation":"settled","schema_version":1,"selected_mode":"hybrid"}'
export GRAPHICS_JSON="$attached"
assert_condition 0

# Attached policy still needs physical NVIDIA hardware.
printf '0x1002\n' >"$LEGION_SYS_PCI_ROOT/0000:01:00.0/vendor"
assert_condition 1
rm "$LEGION_SYS_PCI_ROOT/0000:01:00.0/vendor"
assert_condition 1
printf '0x10de\n' >"$LEGION_SYS_PCI_ROOT/0000:01:00.0/vendor"

export GRAPHICS_EXIT=1
assert_condition 1
unset GRAPHICS_EXIT

for invalid_response in \
  '' 'not-json' 'null' '[]' '{}' \
  '{"schema_version":2,"expected_dgpu_state":"attached"}' \
  '{"schema_version":1,"expected_dgpu_state":"unknown"}' \
  "$attached"$'\n''{"schema_version":1,"expected_dgpu_state":"detached"}'; do
  export GRAPHICS_JSON="$invalid_response"
  assert_condition 1
done

printf 'graphics CDI condition tests passed\n'
