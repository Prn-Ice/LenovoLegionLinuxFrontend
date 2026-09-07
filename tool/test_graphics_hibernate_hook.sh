#!/usr/bin/env bash
set -euo pipefail

# Exercise a Nix-rendered hook, replacing only the two hardware operations.
if [[ $# -ne 1 || ! -f $1 ]]; then
  printf 'Usage: %s RENDERED_HIBERNATE_HOOK\n' "$0" >&2
  exit 64
fi

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
export CALL_LOG="$TMP_DIR/calls"

cat >"$TMP_DIR/reconcile" <<'EOF'
#!/usr/bin/env bash
printf 'reconcile\n' >>"$CALL_LOG"
exit "$RECONCILE_EXIT"
EOF
cat >"$TMP_DIR/cleanup" <<'EOF'
#!/usr/bin/env bash
printf 'cleanup\n' >>"$CALL_LOG"
exit "$CLEANUP_EXIT"
EOF
chmod +x "$TMP_DIR/reconcile" "$TMP_DIR/cleanup"

sed -E \
  -e "s@/nix/store/[^ /]+/bin/legion-graphics-hibernate-reconcile-loop@$TMP_DIR/reconcile@g" \
  -e "s@/nix/store/[^ /]+/bin/legion-graphics-detached-lifecycle@$TMP_DIR/cleanup@g" \
  "$1" >"$TMP_DIR/hook"

if grep -Eq '/bin/legion-graphics-(hibernate-reconcile-loop|detached-lifecycle)' "$TMP_DIR/hook"; then
  printf 'Refusing to run hook with unreplaced hardware operations.\n' >&2
  exit 1
fi

assert_hook() {
  local phase=$1 action=$2 expected_status=$3 expected_calls=$4 actual_status=0
  : >"$CALL_LOG"
  SYSTEMD_SLEEP_ACTION="$action" bash "$TMP_DIR/hook" "$phase" || actual_status=$?
  if [[ $actual_status -ne $expected_status || $(<"$CALL_LOG") != "$expected_calls" ]]; then
    printf 'Hook %s/%s: expected exit %d and calls [%s], got exit %d and calls [%s].\n' \
      "$phase" "$action" "$expected_status" "$expected_calls" \
      "$actual_status" "$(<"$CALL_LOG")" >&2
    exit 1
  fi
}

export RECONCILE_EXIT=2 CLEANUP_EXIT=0
assert_hook post hibernate 2 reconcile
export RECONCILE_EXIT=124
assert_hook post hibernate 124 reconcile
export RECONCILE_EXIT=0
assert_hook post hibernate 0 $'reconcile\ncleanup'
export CLEANUP_EXIT=1
assert_hook post hibernate 1 $'reconcile\ncleanup'
assert_hook pre hibernate 0 ''
assert_hook post suspend 0 ''
assert_hook post '' 0 ''

printf 'graphics hibernate hook tests passed\n'
