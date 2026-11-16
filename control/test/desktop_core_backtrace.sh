#!/usr/bin/env bash
# Run independent GDB commands so one error cannot discard the remaining evidence.

collect_backtrace() {
  local executable=$1 core=$2 prefix=$3 sysroot=$4 backtrace_status=0 maps_status=0
  # GDB, not the shell, expands its $_siginfo convenience variable.
  # shellcheck disable=SC2016
  timeout 120 gdb -q -nx -batch \
    -ex 'set pagination off' -ex 'set print thread-events off' \
    -ex 'set debuginfod enabled off' -ex "set sysroot $sysroot" \
    -ex 'info threads' -ex 'p $_siginfo' -ex 'info registers' \
    -ex 'thread apply all bt full' \
    "$executable" "$core" > "$prefix-all-threads.txt" 2>&1 || backtrace_status=$?
  timeout 90 gdb -q -nx -batch \
    -ex 'set pagination off' -ex 'set debuginfod enabled off' \
    -ex "set sysroot $sysroot" -ex 'info files' -ex 'info sharedlibrary' \
    -ex 'info proc mappings' \
    "$executable" "$core" > "$prefix-library-maps.txt" 2>&1 || maps_status=$?
  printf 'backtrace_status=%s\nmaps_status=%s\n' "$backtrace_status" "$maps_status" \
    > "$prefix-gdb-status.txt"
  if (( backtrace_status != 0 )); then return "$backtrace_status"; fi
  return "$maps_status"
}
