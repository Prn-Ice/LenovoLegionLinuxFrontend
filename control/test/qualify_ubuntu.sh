#!/usr/bin/env bash
# Provision only the disposable Ubuntu VM created by test_portable_distro.sh.
set -euo pipefail
virtual_machine="$(systemd-detect-virt --vm || true)"
if [[ $(id -u) != 0 || ! $virtual_machine =~ ^(qemu|kvm)$ ]]; then
  echo "This qualification setup requires the disposable QEMU VM." >&2
  exit 1
fi
# shellcheck source=/dev/null
source /etc/os-release
if [[ $ID != ubuntu || $VERSION_ID != 22.04 ]]; then
  echo "This qualification setup requires Ubuntu 22.04." >&2
  exit 1
fi
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends cmake ninja-build g++ pkg-config \
  libglib2.0-dev libpolkit-gobject-1-dev policykit-1 dbus python3 util-linux binutils
printf 'legion-control-disposable-lifecycle-vm\n' > /etc/legion-control-lifecycle-test-vm
chmod 644 /etc/legion-control-lifecycle-test-vm
for user in approved denied challenge; do useradd -m -s /bin/bash "$user"; done
mkdir -p /etc/polkit-1/localauthority/50-local.d
# Ubuntu 22.04 uses Polkit's local-authority backend. These test-only decisions
# replace the desktop prompt inside the VM; production keeps the host policy.
cat > /etc/polkit-1/localauthority/50-local.d/io.github.prnice.qualification.pkla <<'EOF'
[Approved fixture user]
Identity=unix-user:approved
Action=org.freedesktop.systemd1.manage-units
ResultAny=yes
ResultInactive=yes
ResultActive=yes

[Denied fixture user]
Identity=unix-user:denied
Action=org.freedesktop.systemd1.manage-units
ResultAny=no
ResultInactive=no
ResultActive=no

[Authentication without an agent]
Identity=unix-user:challenge
Action=org.freedesktop.systemd1.manage-units
ResultAny=auth_admin
ResultInactive=auth_admin
ResultActive=auth_admin
EOF
cmake -S telemetry -B /tmp/native -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=ON \
  -DBUILD_LEGION_CONTROL_SERVICE=ON -DBUILD_PORTABLE_CONTROL_HELPER=ON
cmake --build /tmp/native --parallel 2 --target legion_portable_control \
  package_power_sampler_test control_commands_test graphics_boot_service_test \
  managed_command_test executable_snapshot_test portable_lifetime_test \
  portable_peer_test trusted_executable_test portable_cli_test
cmake -S control/test -B /tmp/fixtures -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build /tmp/fixtures --parallel 2
install -m755 /tmp/fixtures/legion_cli /usr/local/bin/legion_cli
install -m755 /tmp/fixtures/legion-portable-test-client /usr/local/bin/legion-portable-test-client
# The direct command fixture deliberately requires an ordinary user. The two
# ownership checks also run separately as root inside this marked VM.
chown -R approved:approved /tmp/native
runuser -u approved -- ctest --test-dir /tmp/native --output-on-failure --no-tests=error
for check in trusted_executable_test executable_snapshot_test; do
  "/tmp/native/$check" | tee "/tmp/$check.log"
  if grep -q '# SKIP' "/tmp/$check.log"; then
    echo "Root ownership check skipped a case: $check" >&2
    exit 1
  fi
done
# Keep the production helper in a user-owned path, as in an extracted AppImage.
for user in approved denied challenge; do
  install -m755 /tmp/native/legion-portable-control "/home/$user/legion-portable-control"
  chown "$user:$user" "/home/$user/legion-portable-control"
done
systemctl restart polkit.service
python3 control/test/portable_distro_test.py
mkdir -p /root/qualification
cp /tmp/native/legion-portable-control /root/qualification/
cp LICENSE THIRD_PARTY_NOTICES.md /root/qualification/
readelf -lW /root/qualification/legion-portable-control > /root/qualification/elf-program-headers.txt
readelf -dW /root/qualification/legion-portable-control > /root/qualification/elf-dynamic.txt
if grep -E 'RPATH|RUNPATH|/nix/store' /root/qualification/elf-{program-headers,dynamic}.txt; then
  echo 'Distro helper must use host loader paths.' >&2
  exit 1
fi
cp /etc/os-release /root/qualification/os-release
dpkg-query -W systemd libc6 libglib2.0-0 libpolkit-gobject-1-0 policykit-1 > /root/qualification/versions.txt
printf '%s\n' 'Native helper qualification with VM-only synthetic CLI. Hardware, desktop dialogs, and AppImage launch remain unverified.' > /root/qualification/README.txt
tar -czf /root/native-qualification.tar.gz -C /root qualification
