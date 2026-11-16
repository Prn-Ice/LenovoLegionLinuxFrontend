#!/usr/bin/env bash
# Capture core evidence only inside the disposable Debian-package test VM.
set -euo pipefail

usage() {
  echo 'Usage: deb_core_diagnostic.sh prepare OUTPUT_DIRECTORY | collect OUTPUT_DIRECTORY QUALIFICATION_STATUS' >&2
  exit 64
}

if [[ ( $# != 2 && $# != 3 ) || ! $1 =~ ^(prepare|collect)$ ]]; then
  usage
fi
mode=$1
output=$2
if [[ ( $mode == prepare && $# != 2 ) ||
      ( $mode == collect && ( $# != 3 || ! $3 =~ ^[0-9]+$ ) ) ]]; then
  usage
fi
if [[ $(id -u) != 0 || ! $(systemd-detect-virt --vm || true) =~ ^(qemu|kvm)$ ]]; then
  echo 'Core diagnostics require root inside the disposable QEMU VM.' >&2
  exit 1
fi

collect_backtrace() {
  local executable=$1
  local core=$2
  local prefix=$3
  local backtrace_status=0
  local maps_status=0
  timeout 120 gdb -q -nx -batch \
    -ex 'set pagination off' \
    -ex 'set print thread-events off' \
    -ex 'set debuginfod enabled off' \
    -ex 'info threads' \
    -ex 'thread apply all bt full' \
    "$executable" "$core" > "$prefix-all-threads.txt" 2>&1 \
    || backtrace_status=$?
  timeout 90 gdb -q -nx -batch \
    -ex 'set pagination off' \
    -ex 'set debuginfod enabled off' \
    -ex 'info files' \
    -ex 'info sharedlibrary' \
    -ex 'info proc mappings' \
    "$executable" "$core" > "$prefix-library-maps.txt" 2>&1 \
    || maps_status=$?
  printf 'backtrace_status=%s\nmaps_status=%s\n' "$backtrace_status" "$maps_status" \
    > "$prefix-gdb-status.txt"
  (( backtrace_status == 0 && maps_status == 0 ))
}

if [[ $mode == prepare ]]; then
  if [[ -e $output ]]; then
    echo "Diagnostic output already exists: $output" >&2
    exit 1
  fi
  install -d -m 700 "$output"
  install -d /etc/systemd/coredump.conf.d
  cat > /etc/systemd/coredump.conf.d/legion-diagnostic.conf <<'EOF'
[Coredump]
Storage=external
Compress=yes
ProcessSizeMax=2G
ExternalSizeMax=2G
MaxUse=2500M
KeepFree=1G
EOF
  cat > /etc/security/limits.d/99-legion-core-diagnostic.conf <<'EOF'
approved soft core unlimited
approved hard core unlimited
EOF

  soft_limit="$(runuser -u approved -- sh -c 'ulimit -Sc')"
  hard_limit="$(runuser -u approved -- sh -c 'ulimit -Hc')"
  [[ $soft_limit == unlimited && $hard_limit == unlimited ]]
  {
    echo "approved_soft_core_limit=$soft_limit"
    echo "approved_hard_core_limit=$hard_limit"
    runuser -u approved -- sh -c 'grep -F "Max core file size" /proc/$$/limits'
    sysctl kernel.core_pattern kernel.core_uses_pid
    coredumpctl --version
    gdb --version | head -n 1
  } > "$output/core-capture-setup.txt" 2>&1

  fixture_pid_file=/tmp/legion-core-fixture.pid
  rm -f "$fixture_pid_file"
  set +e
  runuser -u approved -- sh -c \
    'echo "$$" > /tmp/legion-core-fixture.pid; exec python3 -c "import os; os.abort()"' \
    > "$output/fixture-abort.log" 2>&1
  fixture_status=$?
  set -e
  echo "$fixture_status" > "$output/fixture-status.txt"
  [[ $fixture_status == 134 ]]
  fixture_pid="$(cat "$fixture_pid_file")"
  [[ $fixture_pid =~ ^[0-9]+$ ]]
  for _ in $(seq 1 30); do
    if coredumpctl --no-pager info "$fixture_pid" \
        > "$output/fixture-coredump-info.txt" 2>&1; then
      break
    fi
    sleep 1
  done
  coredumpctl --no-pager info "$fixture_pid" \
    > "$output/fixture-coredump-info.txt" 2>&1
  timeout 60 coredumpctl --output="$output/fixture.core" dump "$fixture_pid"
  collect_backtrace /usr/bin/python3 "$output/fixture.core" "$output/fixture"
  grep -Fq 'Program terminated with signal SIGABRT' "$output/fixture-all-threads.txt"
  grep -Eq '^#0|^#1' "$output/fixture-all-threads.txt"
  echo 'PASS: approved-user fixture produced a retained core and GDB backtrace'
  exit 0
fi

qualification_status=$3
executable=/usr/lib/legion_frontend/legion_frontend
{
  echo "qualification_status=$qualification_status"
  date --utc --iso-8601=seconds
  uname -a
  cat /etc/os-release
  systemd-detect-virt --vm
  lscpu
  echo
  echo 'Approved-user core limits:'
  runuser -u approved -- sh -c 'ulimit -Sc; ulimit -Hc; grep -F "Max core file size" /proc/$$/limits'
  echo
  echo 'Core handler:'
  sysctl kernel.core_pattern kernel.core_uses_pid
  cat /etc/systemd/coredump.conf.d/legion-diagnostic.conf
  echo
  echo 'Package and source hashes:'
  sha256sum /root/deb-release/*
  echo
  echo 'Relevant package versions:'
  dpkg-query -W systemd systemd-coredump libc6 libgtk-3-0 libglib2.0-0 \
    libegl-mesa0 libgl1-mesa-dri libglx-mesa0 libllvm15
} > "$output/environment.txt" 2>&1

cp -a /home/approved/deb-gui.log /home/approved/desktop-frame-Debian\ package.png \
  "$output/" 2>/dev/null || true
journalctl -b --no-pager > "$output/journal.log"
coredumpctl --no-pager list > "$output/coredump-list.txt" 2>&1 || true

if (( qualification_status == 0 )); then
  echo 'No package failure occurred in the bounded diagnostic run.' \
    | tee "$output/app-core-result.txt"
  exit 0
fi

for _ in $(seq 1 45); do
  if coredumpctl --no-pager -1 info "$executable" \
      > "$output/app-coredump-info.txt" 2>&1; then
    break
  fi
  sleep 1
done
if ! coredumpctl --no-pager -1 info "$executable" \
    > "$output/app-coredump-info.txt" 2>&1; then
  echo 'The package failed, but systemd-coredump retained no app core.' \
    | tee "$output/app-core-result.txt"
  exit 0
fi

timeout 90 coredumpctl --output="$output/legion.core" dump "$executable"
backtrace_status=0
collect_backtrace "$executable" "$output/legion.core" "$output/app" \
  || backtrace_status=$?
awk '$NF ~ /^\// {print $NF}' "$output/app-library-maps.txt" \
  | sort -u > "$output/mapped-files.txt"
while IFS= read -r file; do
  [[ -f $file ]] || continue
  echo "=== $file"
  readelf -n "$file" 2>/dev/null | grep -F 'Build ID:' \
    || echo 'Build ID unavailable'
  dpkg-query -S "$file" 2>/dev/null || true
done < "$output/mapped-files.txt" > "$output/build-ids.txt"
awk '$NF ~ /^\// {print $NF}' "$output/app-library-maps.txt" | sort -u \
  | while IFS= read -r file; do
      if [[ -f $file ]]; then printf '%s\n' "$file"; fi
    done > "$output/guest-library-files.txt"
library_status=0
timeout 45 tar -czf "$output/guest-libraries.tar.gz" \
  --files-from="$output/guest-library-files.txt" 2> "$output/guest-libraries.log" \
  || library_status=$?
echo "library_archive_status=$library_status" >> "$output/app-gdb-status.txt"
stat --format='raw_core_bytes=%s' "$output/legion.core" \
  | tee "$output/app-core-result.txt"
echo "Retained app core evidence in $output; GDB status: $backtrace_status"
if (( backtrace_status != 0 )); then exit "$backtrace_status"; fi
exit "$library_status"
