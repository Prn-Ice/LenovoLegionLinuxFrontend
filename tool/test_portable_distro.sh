#!/usr/bin/env bash
# Test the helper or desktop package in a disposable distro VM.
set -euo pipefail

if [[ ( $# != 3 && $# != 5 ) || ! $2 =~ ^[[:xdigit:]]{64}$ ]]; then
  echo "Usage: bash tool/test_portable_distro.sh IMAGE SHA256 OUTPUT_DIRECTORY [--appimage|--deb RELEASE_DIRECTORY]" >&2
  exit 64
fi

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tool/portable_distro_readiness.sh
source "$root/tool/portable_distro_readiness.sh"
image="$(realpath -- "$1")"
expected="$2"
output="$(realpath -m -- "$3")"
release=
format=native
qualification_archive=native-qualification.tar.gz
if [[ $# == 5 ]]; then
  case "$4" in
    --appimage) format=appimage ;;
    --deb) format=deb ;;
    *) echo "Unknown option: $4" >&2; exit 64 ;;
  esac
  release="$(realpath -- "$5")"
  qualification_archive="$format-qualification.tar.gz"
fi
diagnostic_attempts=${LLLF_DEB_CORE_DIAGNOSTIC_ATTEMPTS:-}
if [[ -n $diagnostic_attempts ]]; then
  if [[ $format != deb || ! $diagnostic_attempts =~ ^([1-9]|1[0-9]|20)$ ]]; then
    echo 'LLLF_DEB_CORE_DIAGNOSTIC_ATTEMPTS requires --deb and a value from 1 to 20.' >&2
    exit 64
  fi
fi
for program in qemu-system-x86_64 qemu-img cloud-localds ssh scp ssh-keygen python3 timeout; do
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
accelerator=${LLLF_VM_ACCELERATOR:-}
if [[ -z $accelerator ]]; then
  accelerator=tcg
  if [[ -r /dev/kvm && -w /dev/kvm ]]; then accelerator=kvm; fi
fi
case "$accelerator" in
  kvm) vm_cpu=host ;;
  tcg) vm_cpu=Nehalem ;;
  *) echo 'LLLF_VM_ACCELERATOR must be kvm or tcg.' >&2; exit 64 ;;
esac
# LLVM can mistake the generic TCG max CPU for a 32-bit AMD processor.
# Use a named 64-bit model for software rendering; KVM uses the host CPU.
echo "Starting disposable distro VM with $accelerator, CPU $vm_cpu; logs: $output"
qemu-system-x86_64 -accel "$accelerator" -cpu "$vm_cpu" -m 2048 -smp 2 -display none \
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
wait_for_cloud_init 180 ssh "${ssh_options[@]}" -p "$port" root@127.0.0.1
export LLLF_QUALIFICATION_COMMIT LLLF_QUALIFICATION_MODIFIED
LLLF_QUALIFICATION_COMMIT="$(git -C "$root" rev-parse HEAD)"
LLLF_QUALIFICATION_MODIFIED="$(git -C "$root" status --porcelain -- control telemetry packaging tool LICENSE THIRD_PARTY_NOTICES.md)"
tar -czf "$output/native-source.tar.gz" -C "$root" control telemetry packaging LICENSE THIRD_PARTY_NOTICES.md
scp "${ssh_options[@]}" -P "$port" "$output/native-source.tar.gz" root@127.0.0.1:/root/source.tar.gz
guest_check=qualify_ubuntu.sh
guest_timeout=900
if [[ -n $release ]]; then
  tar -czf "$scratch/$format-release.tar.gz" -C "$release" .
  scp "${ssh_options[@]}" -P "$port" "$scratch/$format-release.tar.gz" "root@127.0.0.1:/root/$format-release.tar.gz"
  if [[ $format == appimage ]]; then
    guest_check=qualify_appimage_ubuntu.sh
    guest_timeout=1500
  else
    guest_check=qualify_deb.sh
    guest_timeout=1500
  fi
fi
set +e
guest_environment=
if [[ -n $diagnostic_attempts ]]; then
  guest_environment="LLLF_DEB_CORE_DIAGNOSTIC_ATTEMPTS=$diagnostic_attempts "
fi
remote "mkdir /root/source && tar -xzf /root/source.tar.gz -C /root/source && cd /root/source && ${guest_environment}timeout $guest_timeout bash control/test/$guest_check" 2>&1 | tee "$output/qualification.log"
result=${PIPESTATUS[0]}
set -e
remote 'journalctl -b --no-pager' > "$output/journal.log" || true
collection_status=0
if [[ -n $diagnostic_attempts ]]; then
  set +e
  remote "cd /root/source && timeout 360 bash control/test/deb_core_diagnostic.sh collect /root/deb-core-diagnostic $result" \
    2>&1 | tee "$output/core-collection.log"
  collection_status=${PIPESTATUS[0]}
  archive_status=0
  if remote 'test -d /root/deb-core-diagnostic'; then
    remote "set -o pipefail; tar -C /root -cf - deb-core-diagnostic | gzip -1" \
      > "$output/deb-core-diagnostic.tar.gz"
    archive_status=$?
  else
    archive_status=1
  fi
  set -e
  printf 'qualification_status=%s\ncollection_status=%s\narchive_status=%s\n' \
    "$result" "$collection_status" "$archive_status" \
    > "$output/diagnostic-status.txt"
  if (( collection_status == 0 && archive_status != 0 )); then
    collection_status=$archive_status
  fi
fi
if (( result != 0 )); then exit "$result"; fi
if (( collection_status != 0 )); then exit "$collection_status"; fi
scp "${ssh_options[@]}" -P "$port" "root@127.0.0.1:/root/$qualification_archive" "$output/"
export LLLF_QUALIFICATION_OUTPUT="$output" LLLF_QUALIFICATION_IMAGE_SHA256="$expected" LLLF_QUALIFICATION_ARCHIVE="$qualification_archive"
export LLLF_QUALIFICATION_CPU="$vm_cpu"
python3 - <<'PY'
import hashlib
import json
import os
from pathlib import Path

output = Path(os.environ['LLLF_QUALIFICATION_OUTPUT'])
diagnostic_only = bool(os.environ.get('LLLF_DEB_CORE_DIAGNOSTIC_ATTEMPTS'))
manifest = {
    'commit': os.environ['LLLF_QUALIFICATION_COMMIT'],
    'source_worktree_modified': bool(os.environ['LLLF_QUALIFICATION_MODIFIED']),
    'cloud_image_sha256': os.environ['LLLF_QUALIFICATION_IMAGE_SHA256'],
    'cpu_model': os.environ['LLLF_QUALIFICATION_CPU'],
    'files': {name: hashlib.sha256((output / name).read_bytes()).hexdigest()
              for name in ['native-source.tar.gz', os.environ['LLLF_QUALIFICATION_ARCHIVE']]},
    'scope': ('Diagnostic-only Debian close and core capture in a disposable VM'
              if diagnostic_only else
              'Portable control with a synthetic CLI in a disposable distro VM'),
    'release_qualification': not diagnostic_only,
    'hardware': 'unverified',
    'desktop_authentication': 'unverified',
    'appimage': ('FUSE, extraction, desktop launch, and synthetic helper control verified'
                 if os.environ['LLLF_QUALIFICATION_ARCHIVE'] == 'appimage-qualification.tar.gz'
                 else 'unverified'),
    'deb': ('install, desktop, helper, upgrade, and purge verified'
            if os.environ['LLLF_QUALIFICATION_ARCHIVE'] == 'deb-qualification.tar.gz'
            else 'unverified'),
}
(output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
PY
echo "Distro qualification passed: $output"
