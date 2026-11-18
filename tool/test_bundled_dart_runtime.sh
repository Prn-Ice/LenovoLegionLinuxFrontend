#!/usr/bin/env bash
# Evaluate Dart startup with copied libraries in an empty, unprivileged filesystem.
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo 'Usage: bash tool/test_bundled_dart_runtime.sh OUTPUT_DIRECTORY [GLIBC_LIBRARY_DIRECTORY]' >&2
  exit 64
fi

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
output=$(realpath -m -- "$1")
if [[ -e "$output" ]]; then
  echo "Output already exists: $output" >&2
  exit 1
fi
for command in dart bwrap patchelf jq; do
  command -v "$command" >/dev/null
done

bundle="$output/bundle"
mkdir -p "$bundle/lib"
dart compile exe "$root/experiments/check_bundled_dart_runtime.dart" \
  -o "$bundle/runtime-check"
dart compile aot-snapshot "$root/experiments/check_bundled_dart_runtime.dart" \
  -o "$bundle/runtime-check.aot"

sdk_bin=$(dirname -- "$(readlink -f -- "$(command -v dart)")")
cp "$sdk_bin/dartaotruntime" "$bundle/dartaotruntime"
loader=$(patchelf --print-interpreter "$bundle/runtime-check")
library_directory=${2:-$(dirname -- "$loader")}
for name in ld-linux-x86-64.so.2 libc.so.6 libm.so.6 libdl.so.2 libpthread.so.0; do
  cp -L "$library_directory/$name" "$bundle/lib/$name"
done

cp "$bundle/runtime-check" "$bundle/runtime-check-patched"
patchelf --set-interpreter /bundle/lib/ld-linux-x86-64.so.2 \
  --set-rpath /bundle/lib "$bundle/runtime-check-patched"

# Expose no host libraries, SDK, commands, network, or privileged service.
run_isolated() {
  bwrap --unshare-all --die-with-parent --clearenv \
    --ro-bind "$bundle" /bundle --proc /proc --dev /dev --tmpfs /tmp \
    --chdir / "$@"
}

direct_status=0
run_isolated /bundle/lib/ld-linux-x86-64.so.2 --inhibit-cache \
  --library-path /bundle/lib /bundle/runtime-check \
  > "$output/direct-loader.log" 2>&1 || direct_status=$?

patched_status=0
run_isolated /bundle/runtime-check-patched \
  > "$output/patched-executable.log" 2>&1 || patched_status=$?

snapshot_status=0
run_isolated /bundle/lib/ld-linux-x86-64.so.2 --inhibit-cache \
  --library-path /bundle/lib /bundle/dartaotruntime /bundle/runtime-check.aot \
  > "$output/aot-snapshot.json" 2> "$output/aot-snapshot.stderr" || snapshot_status=$?

# Hide one required library to check that the host cannot supply it.
missing_library_status=0
bwrap --unshare-all --die-with-parent --clearenv \
  --ro-bind "$bundle" /bundle --tmpfs /bundle/lib \
  --ro-bind "$bundle/lib/ld-linux-x86-64.so.2" /bundle/lib/ld-linux-x86-64.so.2 \
  --ro-bind "$bundle/lib/libc.so.6" /bundle/lib/libc.so.6 \
  --ro-bind "$bundle/lib/libdl.so.2" /bundle/lib/libdl.so.2 \
  --ro-bind "$bundle/lib/libpthread.so.0" /bundle/lib/libpthread.so.0 \
  --proc /proc --dev /dev --tmpfs /tmp --chdir / \
  /bundle/lib/ld-linux-x86-64.so.2 --inhibit-cache --library-path /bundle/lib \
  /bundle/dartaotruntime /bundle/runtime-check.aot \
  > "$output/missing-library.log" 2>&1 || missing_library_status=$?

jq -n --arg libraryDirectory "$(realpath -- "$library_directory")" \
  --argjson direct "$direct_status" --argjson patched "$patched_status" \
  --argjson snapshot "$snapshot_status" --argjson missing "$missing_library_status" \
  '{libraryDirectory: $libraryDirectory, exitCodes: {
    directLoader: $direct, patchedExecutable: $patched,
    aotSnapshot: $snapshot, missingLibrary: $missing
  }}' > "$output/results.json"
cat "$output/results.json"

test "$snapshot_status" -eq 0
jq -e '
  .filePassed and .peerPassed and
  (.mappedFiles | length > 0) and
  all(.mappedFiles[]; startswith("/bundle/"))
' "$output/aot-snapshot.json" >/dev/null
test "$missing_library_status" -ne 0
grep -q 'libm.so.6' "$output/missing-library.log"
echo "Bundled runtime checks passed. Results: $output"
