#!/usr/bin/env bash
# Build and test the portable helper inside a disposable Ubuntu cloud VM.
set -euo pipefail

if [[ $# != 3 || ! $2 =~ ^[[:xdigit:]]{64}$ ]]; then
  echo "Usage: bash tool/test_portable_distro.sh IMAGE SHA256 OUTPUT_DIRECTORY" >&2
  exit 64
fi

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
image="$(realpath -- "$1")"
expected="$2"
output="$(realpath -m -- "$3")"
for program in qemu-system-x86_64 qemu-img cloud-localds ssh scp ssh-keygen python3; do
  if ! command -v "$program" >/dev/null; then
    echo "Required program is missing: $program" >&2
    exit 1
  fi
done
if ! printf '%s  %s\n' "$expected" "$image" | sha256sum --check --status; then
  echo "Cloud image checksum does not match: $image" >&2
  exit 1
fi
if [[ -e $output ]]; then
  echo "Output already exists: $output" >&2
  exit 1
fi
mkdir -p -- "$output"
scratch="$(mktemp -d /tmp/legion-distro-vm.XXXXXXXX)"
vm_pid=
cleanup() {
  if [[ -n $vm_pid ]]; then
    kill "$vm_pid" 2>/dev/null || true
    wait "$vm_pid" 2>/dev/null || true
  fi
  rm -rf -- "$scratch"
}
trap cleanup EXIT
ssh-keygen -q -t ed25519 -N '' -f "$scratch/key"
public_key="$(cat "$scratch/key.pub")"
cat > "$scratch/user-data" <<EOF
#cloud-config
disable_root: false
ssh_pwauth: false
users:
  - name: root
    ssh_authorized_keys:
      - $public_key
EOF
printf 'instance-id: legion-distro-qualification\nlocal-hostname: legion-distro-vm\n' > "$scratch/meta-data"
cloud-localds "$scratch/seed.img" "$scratch/user-data" "$scratch/meta-data"
qemu-img create -q -f qcow2 -F qcow2 -b "$image" "$scratch/disk.qcow2" 8G
# Bind SSH to loopback. The cloud image and host filesystem are never mounted
# into the guest; only the native source archive is copied over SSH.
port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
accelerator=tcg
if [[ -r /dev/kvm && -w /dev/kvm ]]; then accelerator=kvm; fi
echo "Starting disposable Ubuntu VM with $accelerator; logs: $output"
qemu-system-x86_64 -accel "$accelerator" -m 2048 -smp 2 -display none \
  -serial "file:$output/serial.log" -monitor none -no-reboot \
  -drive "file=$scratch/disk.qcow2,if=virtio,format=qcow2" \
  -drive "file=$scratch/seed.img,if=virtio,format=raw,readonly=on" \
  -netdev "user,id=net,hostfwd=tcp:127.0.0.1:$port-:22" \
  -device virtio-net-pci,netdev=net > "$output/qemu.log" 2>&1 &
vm_pid=$!
ssh_options=(-i "$scratch/key" -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes
  -o "UserKnownHostsFile=$scratch/known_hosts" -o ConnectTimeout=3 -o BatchMode=yes)
# Learn this VM's fresh key once; subsequent connections require that same key.
deadline=$((SECONDS + 180))
until ssh -o StrictHostKeyChecking=accept-new "${ssh_options[@]}" -p "$port" root@127.0.0.1 true 2>/dev/null; do
  if ! kill -0 "$vm_pid" 2>/dev/null || (( SECONDS >= deadline )); then
    echo "VM did not become ready; see $output/serial.log and qemu.log" >&2
    exit 1
  fi
  sleep 1
done
remote() { ssh "${ssh_options[@]}" -p "$port" root@127.0.0.1 "$@"; }
remote 'timeout 180 cloud-init status --wait'
export LLLF_QUALIFICATION_COMMIT LLLF_QUALIFICATION_MODIFIED
LLLF_QUALIFICATION_COMMIT="$(git -C "$root" rev-parse HEAD)"
LLLF_QUALIFICATION_MODIFIED="$(git -C "$root" status --porcelain -- control telemetry packaging LICENSE THIRD_PARTY_NOTICES.md)"
tar -czf "$output/native-source.tar.gz" -C "$root" control telemetry packaging LICENSE THIRD_PARTY_NOTICES.md
scp "${ssh_options[@]}" -P "$port" "$output/native-source.tar.gz" root@127.0.0.1:/root/source.tar.gz
set +e
remote 'mkdir /root/source && tar -xzf /root/source.tar.gz -C /root/source && cd /root/source && timeout 600 bash control/test/qualify_ubuntu.sh' 2>&1 | tee "$output/qualification.log"
result=${PIPESTATUS[0]}
set -e
remote 'journalctl -b --no-pager' > "$output/journal.log" || true
if (( result != 0 )); then exit "$result"; fi
scp "${ssh_options[@]}" -P "$port" root@127.0.0.1:/root/native-qualification.tar.gz "$output/"
export LLLF_QUALIFICATION_OUTPUT="$output" LLLF_QUALIFICATION_IMAGE_SHA256="$expected"
python3 - <<'PY'
import hashlib
import json
import os
from pathlib import Path

output = Path(os.environ['LLLF_QUALIFICATION_OUTPUT'])
manifest = {
    'commit': os.environ['LLLF_QUALIFICATION_COMMIT'],
    'source_worktree_modified': bool(os.environ['LLLF_QUALIFICATION_MODIFIED']),
    'cloud_image_sha256': os.environ['LLLF_QUALIFICATION_IMAGE_SHA256'],
    'files': {name: hashlib.sha256((output / name).read_bytes()).hexdigest()
              for name in ['native-source.tar.gz', 'native-qualification.tar.gz']},
    'scope': 'Native helper with a synthetic CLI in a disposable Ubuntu VM',
    'hardware': 'unverified',
    'desktop_authentication': 'unverified',
    'appimage': 'unverified',
}
(output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
PY
echo "Distro qualification passed: $output"
