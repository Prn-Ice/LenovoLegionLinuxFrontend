#!/usr/bin/env bash
set -euo pipefail

# Test the Nix-rendered timeout wrapper without invoking hardware operations.
if [[ $# -ne 1 || ! -f $1 ]]; then
  printf 'Usage: %s RENDERED_S2H_PREFLIGHT\n' "$0" >&2
  exit 64
fi
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
cat >"$TMP_DIR/lifecycle" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ $# == 3 && $2 == preflight ]] || exit 64
if [[ "$TEST_RESULT" == hang ]]; then
  exec sleep 40
fi
exit "$TEST_RESULT"
EOF
chmod +x "$TMP_DIR/lifecycle"
sed -E \
  "s@/nix/store/[^ /]+/bin/legion-graphics-detached-lifecycle@$TMP_DIR/lifecycle@g" \
  "$1" >"$TMP_DIR/preflight"
if grep -q '/bin/legion-graphics-detached-lifecycle' "$TMP_DIR/preflight"; then
  printf 'Refusing to run a preflight with unreplaced hardware operations.\n' >&2
  exit 1
fi
for expected in 0 1 2 124; do
  export TEST_RESULT=$expected
  [[ $expected != 124 ]] || TEST_RESULT=hang
  actual=0
  bash "$TMP_DIR/preflight" || actual=$?
  if [[ $actual != "$expected" ]]; then
    printf 'Expected exit %s, got %s.\n' "$expected" "$actual" >&2
    exit 1
  fi
done
printf 'graphics suspend-then-hibernate preflight wrapper tests passed\n'
