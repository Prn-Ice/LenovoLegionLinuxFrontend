#!/usr/bin/env bash
# Reuse the hosted package diagnostic's fixture and failure collection sequence.
set -euo pipefail
[[ $# == 2 || $# == 3 ]]
mode=$1
output=$2
[[ $mode == prepare || $mode == collect ]]
[[ $(id -u) == 0 && $(systemd-detect-virt --vm || true) == kvm ]]

collect_backtrace() {
  local executable=$1 core=$2 prefix=$3 backtrace_status=0 maps_status=0
  timeout 120 gdb -q -nx -batch \
    -ex 'set pagination off' -ex 'set print thread-events off' \
    -ex 'set debuginfod enabled off' -ex 'info threads' \
    -ex 'p $_siginfo' -ex 'info registers' -ex 'thread apply all bt full' \
    "$executable" "$core" > "$prefix-all-threads.txt" 2>&1 || backtrace_status=$?
  timeout 90 gdb -q -nx -batch \
    -ex 'set pagination off' -ex 'set debuginfod enabled off' \
    -ex 'info files' -ex 'info sharedlibrary' -ex 'info proc mappings' \
    "$executable" "$core" > "$prefix-library-maps.txt" 2>&1 || maps_status=$?
  printf 'backtrace_status=%s\nmaps_status=%s\n' "$backtrace_status" "$maps_status" \
    > "$prefix-gdb-status.txt"
  (( backtrace_status == 0 && maps_status == 0 ))
}

if [[ $mode == prepare ]]; then
  [[ $# == 2 && ! -e $output ]]
  install -d -m 700 "$output"
  install -d /etc/systemd/coredump.conf.d
  cat > /etc/systemd/coredump.conf.d/template-diagnostic.conf <<'EOF'
[Coredump]
Storage=external
Compress=yes
ProcessSizeMax=2G
ExternalSizeMax=2G
MaxUse=2500M
KeepFree=1G
EOF
  cat > /etc/security/limits.d/99-template-core-diagnostic.conf <<'EOF'
approved soft core unlimited
approved hard core unlimited
EOF
  soft_limit="$(runuser -u approved -- sh -c 'ulimit -Sc')"
  hard_limit="$(runuser -u approved -- sh -c 'ulimit -Hc')"
  [[ $soft_limit == unlimited && $hard_limit == unlimited ]]
  {
    echo "approved_soft_core_limit=$soft_limit"
    echo "approved_hard_core_limit=$hard_limit"
    sysctl kernel.core_pattern kernel.core_uses_pid
    coredumpctl --version
    gdb --version | head -n 1
  } > "$output/core-capture-setup.txt" 2>&1
  set +e
  runuser -u approved -- sh -c \
    'echo "$$" > /tmp/template-core-fixture.pid; exec python3 -c "import os; os.abort()"' \
    > "$output/fixture-abort.log" 2>&1
  fixture_status=$?
  set -e
  echo "$fixture_status" > "$output/fixture-status.txt"
  [[ $fixture_status == 134 ]]
  fixture_pid="$(cat /tmp/template-core-fixture.pid)"
  [[ $fixture_pid =~ ^[0-9]+$ ]]
  for _ in $(seq 1 30); do
    if coredumpctl --no-pager info "$fixture_pid" > "$output/fixture-coredump-info.txt" 2>&1; then break; fi
    sleep 1
  done
  coredumpctl --no-pager info "$fixture_pid" > "$output/fixture-coredump-info.txt" 2>&1
  timeout 60 coredumpctl --output="$output/fixture.core" dump "$fixture_pid"
  collect_backtrace /usr/bin/python3 "$output/fixture.core" "$output/fixture"
  grep -Fq 'Program terminated with signal SIGABRT' "$output/fixture-all-threads.txt"
  grep -Eq '^#0|^#1' "$output/fixture-all-threads.txt"
  echo 'PASS: controlled abort retained its core and all-thread GDB trace before template launch'
  exit 0
fi

[[ $# == 3 && $3 =~ ^[0-9]+$ ]]
diagnostic_status=$3
executable=/opt/shutdown-template/shutdown_template
mkdir -p "$output"
{
  echo "diagnostic_status=$diagnostic_status"
  date --utc --iso-8601=seconds
  uname -a
  cat /etc/os-release
  systemd-detect-virt --vm
  lscpu
  echo 'Relevant package versions:'
  dpkg-query -W systemd systemd-coredump libc6 libgtk-3-0 libglib2.0-0 \
    libegl-mesa0 libgl1-mesa-dri libglx-mesa0 libllvm15 at-spi2-core openbox
  echo 'Template input hashes:'
  if [[ -d /root/template-release ]]; then sha256sum /root/template-release/*; fi
} > "$output/environment.txt" 2>&1
if [[ -d /root/template-release ]]; then
  cp /root/template-release/{template-manifest.json,template-source.sha256,SHA256SUMS} "$output/"
fi
find /home/approved -maxdepth 1 -type f \
  \( -name 'template-*.log' -o -name 'template-*.png' -o -name 'template-*-maps.txt' \
     -o -name 'openbox.log' -o -name 'launch-environment.json' \) \
  -exec cp -t "$output/" {} +
journalctl -b --no-pager > "$output/journal.log"
coredumpctl --no-pager list > "$output/coredump-list.txt" 2>&1 || true
if (( diagnostic_status == 0 )); then
  echo 'No template failure occurred in 20 required closes; original app failure remains unresolved.' \
    | tee "$output/app-core-result.txt"
  exit 0
fi
for _ in $(seq 1 45); do
  if coredumpctl --no-pager -1 info "$executable" > "$output/app-coredump-info.txt" 2>&1; then break; fi
  sleep 1
done
if ! coredumpctl --no-pager -1 info "$executable" > "$output/app-coredump-info.txt" 2>&1; then
  echo 'Diagnostic failed but systemd-coredump retained no template core.' | tee "$output/app-core-result.txt"
  exit 0
fi
timeout 90 coredumpctl --output="$output/template.core" dump "$executable"
backtrace_status=0
collect_backtrace "$executable" "$output/template.core" "$output/app" || backtrace_status=$?
awk '$NF ~ /^\// {print $NF}' "$output/app-library-maps.txt" | sort -u > "$output/mapped-files.txt"
while IFS= read -r file; do
  [[ -f $file ]] || continue
  echo "=== $file"
  readelf -n "$file" 2>/dev/null | grep -F 'Build ID:' || echo 'Build ID unavailable'
  dpkg-query -S "$file" 2>/dev/null || true
done < "$output/mapped-files.txt" > "$output/build-ids.txt"
while IFS= read -r file; do
  if [[ -f $file ]]; then printf '%s\n' "$file"; fi
done < "$output/mapped-files.txt" > "$output/guest-library-files.txt"
library_status=0
timeout 45 tar -czf "$output/guest-libraries.tar.gz" \
  --files-from="$output/guest-library-files.txt" 2> "$output/guest-libraries.log" || library_status=$?
stat --format='raw_core_bytes=%s' "$output/template.core" | tee "$output/app-core-result.txt"
echo "library_archive_status=$library_status" >> "$output/app-gdb-status.txt"
if (( backtrace_status != 0 )); then exit "$backtrace_status"; fi
exit "$library_status"
