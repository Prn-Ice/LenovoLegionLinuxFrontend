#!/usr/bin/env bash
# Check failure archives and exit status at the Nix command boundary.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
temporary=$(mktemp -d)
trap 'rm -rf -- "$temporary"' EXIT
mkdir "$temporary/bin"
export REAL_TAR
REAL_TAR=$(command -v tar)
cat >"$temporary/bin/nix" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ $1 == eval ]]; then
  printf '%s' "$FIXTURE_OUTPUT"
  exit 0
fi
[[ $1 == build ]]
echo 'VM diagnostic output'
if [[ ${MISSING_OUTPUT:-0} == 0 ]]; then
  mkdir -p "$FIXTURE_OUTPUT/gui-evidence" "$FIXTURE_OUTPUT/wayland-diagnostics"
  for file in gui.log sway.log wayland.log wayland-launcher.log; do
    echo 'guest evidence' >"$FIXTURE_OUTPUT/$file"
  done
  echo 'screenshot fixture' >"$FIXTURE_OUTPUT/gui-evidence/failure.png"
fi
if [[ $NIX_STATUS == 0 ]]; then
  while [[ $1 != --out-link ]]; do shift; done
  ln -s "$FIXTURE_OUTPUT" "$2"
fi
exit "$NIX_STATUS"
EOF
cat >"$temporary/bin/tar" <<'EOF'
#!/usr/bin/env bash
if [[ ${ARCHIVE_STATUS:-0} != 0 ]]; then exit "$ARCHIVE_STATUS"; fi
exec "$REAL_TAR" "$@"
EOF
chmod +x "$temporary/bin/"*
export PATH="$temporary/bin:$PATH"
printf 'AppImage fixture\n' >"$temporary/image"

check_run() {
  local name=$1 expected=$2 actual=0
  export FIXTURE_OUTPUT="$temporary/raw-$name"
  bash "$root/tool/ci/test_appimage_nixos.sh" "$temporary/image" "$temporary/$name" \
    >"$temporary/$name.log" 2>&1 || actual=$?
  [[ $actual == "$expected" ]] || {
    cat "$temporary/$name.log" >&2
    echo "Expected status $expected, got $actual for $name" >&2
    exit 1
  }
}

export NIX_STATUS=23
check_run failed 23
[[ ! -e $temporary/failed/manifest.json && ! -e $temporary/failed/result ]]
tar -tzf "$temporary/failed/appimage-nixos-failure-evidence.tar.gz" >"$temporary/files"
grep -Fxq build-and-vm.log "$temporary/files"
grep -Fxq gui.log "$temporary/files"
grep -Fxq gui-evidence/failure.png "$temporary/files"
echo 'PASS: a failed build retains guest evidence without qualification metadata'

export MISSING_OUTPUT=1
check_run missing 23
tar -tzf "$temporary/missing/appimage-nixos-failure-evidence.tar.gz" >"$temporary/files"
[[ $(cat "$temporary/files") == build-and-vm.log ]]
unset MISSING_OUTPUT
export ARCHIVE_STATUS=7
check_run archive-error 23
[[ ! -e $temporary/archive-error/manifest.json ]]
unset ARCHIVE_STATUS
echo 'PASS: missing guest output and archive errors preserve the build failure'

export NIX_STATUS=0
check_run passed 0
[[ -f $temporary/passed/manifest.json && -L $temporary/passed/result ]]
[[ ! -e $temporary/passed/appimage-nixos-failure-evidence.tar.gz ]]
tar -tzf "$temporary/passed/appimage-nixos-qualification.tar.gz" >"$temporary/files"
grep -Fxq manifest.json "$temporary/files"
grep -Fxq gui.log "$temporary/files"
echo 'PASS: successful builds retain the qualification manifest and archive'
