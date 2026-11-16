#!/usr/bin/env bash
# Reuse the controlled abort and independent GDB capture in the disposable guest.
set -euo pipefail
[[ $# == 2 || $# == 3 ]]
mode=$1 output=$2
[[ $(id -u) == 0 && $(systemd-detect-virt --vm || true) == kvm ]]
# shellcheck source=control/test/desktop_core_backtrace.sh
source control/test/desktop_core_backtrace.sh

if [[ $mode == prepare ]]; then
  [[ $# == 2 && ! -e $output ]]
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
    sysctl kernel.core_pattern kernel.core_uses_pid
    coredumpctl --version
    gdb --version | head -n 1
  } > "$output/core-capture-setup.txt" 2>&1
  fixture_status=0
  runuser -u approved -- sh -c \
    'echo "$$" > /tmp/legion-core-fixture.pid; exec python3 -c "import os; os.abort()"' \
    > "$output/fixture-abort.log" 2>&1 || fixture_status=$?
  echo "$fixture_status" > "$output/fixture-status.txt"
  [[ $fixture_status == 134 ]]
  fixture_pid="$(cat /tmp/legion-core-fixture.pid)"
  [[ $fixture_pid =~ ^[0-9]+$ ]]
  for _ in $(seq 1 30); do
    if timeout 5 coredumpctl --no-pager info "$fixture_pid" \
        > "$output/fixture-coredump-info.txt" 2>&1; then break; fi
    sleep 1
  done
  timeout 10 coredumpctl --no-pager info "$fixture_pid" > "$output/fixture-coredump-info.txt" 2>&1
  timeout 60 coredumpctl --output="$output/fixture.core" dump "$fixture_pid"
  collect_backtrace /usr/bin/python3 "$output/fixture.core" "$output/fixture" /
  grep -Fq 'Program terminated with signal SIGABRT' "$output/fixture-all-threads.txt"
  grep -Eq '^#0|^#1' "$output/fixture-all-threads.txt"
  echo 'PASS: controlled approved-user abort retained its core and all-thread GDB trace before app launch'
  exit 0
fi

[[ $mode == collect && $# == 3 && $3 =~ ^[0-9]+$ ]]
qualification_status=$3
mkdir -p "$output"
collection_status=0
capture() {
  local name=$1 status=0
  shift
  timeout 120 "$@" > "$output/$name.txt" 2>&1 || status=$?
  printf '%s=%s\n' "$name" "$status" >> "$output/collection-status.txt"
  if (( status != 0 )); then collection_status=1; fi
  return 0
}
echo "qualification=$qualification_status" > "$output/collection-status.txt"
capture date date --utc --iso-8601=seconds
capture uname uname -a
capture os-release cat /etc/os-release
capture cpu lscpu
capture cpuinfo cat /proc/cpuinfo
capture versions dpkg-query -W systemd systemd-coredump libc6 libglib2.0-0 \
  libegl-mesa0 libgl1-mesa-dri libglx-mesa0 libllvm15 at-spi2-core python3-xlib gdb mesa-utils openbox wmctrl
capture core-handler sysctl kernel.core_pattern kernel.core_uses_pid
capture journal journalctl -b --no-pager
capture coredump-list coredumpctl --no-pager list
capture input-hashes bash -c 'sha256sum /home/approved/"AppImage with spaces"/*'
capture ordinary-evidence cp /root/appimage-qualification.tar.gz "$output/ordinary-evidence.tar.gz"
capture desktop-evidence cp -a /home/approved/appimage-diagnostic "$output/desktop"

for phase in fuse extracted; do
  directory="$output/desktop/$phase"
  [[ -f $directory/process.json ]] || continue
  pid="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["pid"])' "$directory/process.json")"
  executable="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["executable"])' "$directory/process.json")"
  capture "$phase-build-ids" python3 -c '
import pathlib, subprocess, sys
for path in sorted(pathlib.Path(sys.argv[1]).rglob("*")):
    if not path.is_file():
        continue
    with path.open("rb") as source:
        if source.read(4) != b"\x7fELF":
            continue
    result = subprocess.run(["readelf", "-n", str(path)], text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10)
    print(f"FILE {path} STATUS {result.returncode}\n{result.stdout}", flush=True)
' "$directory/rootfs"
  if [[ -f $directory/exit.json ]] && python3 -c \
      'import json,sys; sys.exit(json.load(open(sys.argv[1]))["status"] != 0)' "$directory/exit.json"; then
    echo "$phase=normal_exit_no_app_core" >> "$output/app-core-result.txt"
    continue
  fi
  for _ in $(seq 1 30); do
    if timeout 5 coredumpctl --no-pager info "$pid" > "$output/$phase-coredump-info.txt" 2>&1; then break; fi
    sleep 1
  done
  capture "$phase-coredump-info" coredumpctl --no-pager info "$pid"
  capture "$phase-core-dump" coredumpctl --output="$output/$phase.core" dump "$pid"
  status=0
  collect_backtrace "$directory/rootfs$executable" "$output/$phase.core" \
    "$output/$phase" "$directory/rootfs" || status=$?
  echo "$phase-gdb=$status" >> "$output/collection-status.txt"
  if (( status != 0 )); then collection_status=1; fi
  capture "$phase-core-size" stat --format='raw_core_bytes=%s' "$output/$phase.core"
done
# The inner shell receives the evidence directory as $1.
# shellcheck disable=SC2016
capture evidence-hashes bash -c 'find "$1" -type f ! -name evidence-hashes.txt ! -name collection-status.txt -print0 | sort -z | xargs -0 -r sha256sum' _ "$output"
exit "$collection_status"
