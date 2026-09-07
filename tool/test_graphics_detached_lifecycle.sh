#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
LIFECYCLE="$SCRIPT_DIR/../packaging/nixos/legion-graphics-detached-lifecycle.sh"
command -v jq >/dev/null || {
  printf 'jq is required; run this test through nix shell nixpkgs#jq.\n' >&2
  exit 127
}
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
export LEGION_SYS_MODULE_ROOT="$TMP_DIR/sys-module"
export LEGION_DEV_ROOT="$TMP_DIR/dev"
mkdir -p "$LEGION_SYS_MODULE_ROOT" "$LEGION_DEV_ROOT"

write_fake_cli() {
  local body=$1
  {
    printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail'
    printf '%s\n' "$body"
  } >"$TMP_DIR/legion_cli"
  chmod +x "$TMP_DIR/legion_cli"
}

cat >"$TMP_DIR/modprobe" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$MODPROBE_LOG"
[[ "${MODPROBE_FAIL:-0}" == 0 ]] || exit 1
shift
for module in "$@"; do
  rmdir "$LEGION_SYS_MODULE_ROOT/$module"
done
EOF
chmod +x "$TMP_DIR/modprobe"
export MODPROBE_LOG="$TMP_DIR/modprobe.log"

run_lifecycle() {
  bash "$LIFECYCLE" "$TMP_DIR/legion_cli" "$1" "$TMP_DIR/modprobe"
}

assert_status() {
  local expected=$1
  shift
  set +e
  "$@" >"$TMP_DIR/stdout" 2>"$TMP_DIR/stderr"
  local actual=$?
  set -e
  if [[ $actual -ne $expected ]]; then
    printf 'Expected exit %d, got %d.\nstdout:\n' "$expected" "$actual" >&2
    cat "$TMP_DIR/stdout" >&2
    printf 'stderr:\n' >&2
    cat "$TMP_DIR/stderr" >&2
    exit 1
  fi
}

detached='{"schema_version":1,"effective_dgpu_state":"detached","expected_dgpu_state":"detached","reconciliation":"settled","client_inspection_complete":true,"active_clients":[]}'
attached='{"schema_version":1,"effective_dgpu_state":"attached","expected_dgpu_state":"attached","reconciliation":"settled","client_inspection_complete":true,"active_clients":[]}'
client='{"schema_version":1,"effective_dgpu_state":"detached","expected_dgpu_state":"detached","reconciliation":"settled","client_inspection_complete":true,"active_clients":[{"pid":4242,"comm":"kwin_wayland","devices":["/dev/nvidiactl"]}]}'
incomplete='{"schema_version":1,"effective_dgpu_state":"detached","expected_dgpu_state":"detached","reconciliation":"settled","client_inspection_complete":false,"active_clients":[]}'

write_fake_cli "printf '%s\\n' '$detached'"
assert_status 0 run_lifecycle preflight
[[ ! -e "$MODPROBE_LOG" ]]

write_fake_cli "printf '%s\\n' '$client'"
assert_status 2 run_lifecycle preflight
[[ ! -e "$MODPROBE_LOG" ]]

write_fake_cli "printf '%s\\n' '$incomplete'"
assert_status 2 run_lifecycle preflight
[[ ! -e "$MODPROBE_LOG" ]]

mkdir -p \
  "$LEGION_SYS_MODULE_ROOT/nvidia_drm" \
  "$LEGION_SYS_MODULE_ROOT/nvidia_uvm" \
  "$LEGION_SYS_MODULE_ROOT/nvidia_modeset" \
  "$LEGION_SYS_MODULE_ROOT/nvidia" \
  "$LEGION_DEV_ROOT/nvidia-caps"
touch \
  "$LEGION_DEV_ROOT/nvidia0" \
  "$LEGION_DEV_ROOT/nvidiactl" \
  "$LEGION_DEV_ROOT/nvidia-modeset" \
  "$LEGION_DEV_ROOT/nvidia-uvm" \
  "$LEGION_DEV_ROOT/nvidia-uvm-tools" \
  "$LEGION_DEV_ROOT/nvidia-caps/nvidia-cap1"
write_fake_cli "printf '%s\\n' '$detached'"
assert_status 0 run_lifecycle cleanup
[[ $(<"$MODPROBE_LOG") == "--remove nvidia_drm nvidia_uvm nvidia_modeset nvidia" ]]
[[ ! -e "$LEGION_DEV_ROOT/nvidiactl" ]]
[[ ! -d "$LEGION_DEV_ROOT/nvidia-caps" ]]

rm -f "$MODPROBE_LOG"
mkdir -p "$LEGION_SYS_MODULE_ROOT/nvidia"
touch "$LEGION_DEV_ROOT/nvidiactl"
write_fake_cli "printf '%s\\n' '$attached'"
assert_status 0 run_lifecycle cleanup
[[ -d "$LEGION_SYS_MODULE_ROOT/nvidia" ]]
[[ -e "$LEGION_DEV_ROOT/nvidiactl" ]]
[[ ! -e "$MODPROBE_LOG" ]]
rmdir "$LEGION_SYS_MODULE_ROOT/nvidia"
rm "$LEGION_DEV_ROOT/nvidiactl"

mkdir -p "$LEGION_SYS_MODULE_ROOT/nvidia"
touch "$LEGION_DEV_ROOT/nvidiactl"
write_fake_cli "printf '%s\\n' '$detached'"
export MODPROBE_FAIL=1
assert_status 1 run_lifecycle cleanup
unset MODPROBE_FAIL
[[ -d "$LEGION_SYS_MODULE_ROOT/nvidia" ]]
[[ -e "$LEGION_DEV_ROOT/nvidiactl" ]]

printf 'graphics detached lifecycle tests passed\n'
