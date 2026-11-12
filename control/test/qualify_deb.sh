#!/usr/bin/env bash
# Provision and install packages only inside the disposable acceptance VM.
set -euo pipefail
virtual_machine="$(systemd-detect-virt --vm || true)"
if [[ $(id -u) != 0 || ! $virtual_machine =~ ^(qemu|kvm)$ ]]; then
  echo 'Debian package qualification requires the disposable QEMU VM.' >&2
  exit 1
fi
# shellcheck source=/dev/null
source /etc/os-release
if [[ $ID:$VERSION_ID != ubuntu:22.04 && $ID:$VERSION_ID != debian:12 ]]; then
  echo 'This check supports Ubuntu 22.04 and Debian 12.' >&2
  exit 1
fi
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends policykit-1 dbus python3 util-linux \
  libgtk-3-0 libgl1-mesa-dri libglx-mesa0 libegl1 libegl-mesa0 libgles2 \
  gsettings-desktop-schemas xvfb xauth xdotool desktop-file-utils appstream
printf 'legion-control-disposable-lifecycle-vm\n' > /etc/legion-control-lifecycle-test-vm
chmod 644 /etc/legion-control-lifecycle-test-vm
for user in approved denied challenge; do useradd -m -s /bin/bash "$user"; done
if [[ $ID == ubuntu ]]; then
  mkdir -p /etc/polkit-1/localauthority/50-local.d
  cat > /etc/polkit-1/localauthority/50-local.d/legion-package-test.pkla <<'EOF'
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
else
  mkdir -p /etc/polkit-1/rules.d
  cat > /etc/polkit-1/rules.d/50-legion-package-test.rules <<'EOF'
polkit.addRule(function(action, subject) {
  if (action.id != "org.freedesktop.systemd1.manage-units") return;
  if (subject.user == "approved") return polkit.Result.YES;
  if (subject.user == "denied") return polkit.Result.NO;
  if (subject.user == "challenge") return polkit.Result.AUTH_ADMIN;
});
EOF
fi
mkdir -p /root/deb-release /tmp/fixtures
tar -xzf /root/deb-release.tar.gz -C /root/deb-release
python3 - <<'PY'
import hashlib
import json
from pathlib import Path
import tarfile

directory = Path('/root/deb-release')
manifest = json.loads(next(directory.glob('legion-frontend-*.json')).read_text())
fixtures = directory / 'vm-fixtures.tar.gz'
assert hashlib.sha256(fixtures.read_bytes()).hexdigest() == manifest['vm_fixtures_sha256']
with tarfile.open(fixtures) as archive:
    assert set(archive.getnames()) == {'legion_cli', 'legion-portable-test-client'}
    assert all(member.isfile() for member in archive.getmembers())
    for member in archive.getmembers():
        target = Path('/tmp/fixtures') / member.name
        target.write_bytes(archive.extractfile(member).read())
        target.chmod(0o755)
PY
install -m755 /tmp/fixtures/legion_cli /usr/local/bin/legion_cli
install -m755 /tmp/fixtures/legion-portable-test-client /usr/local/bin/legion-portable-test-client
systemctl restart polkit.service
mkdir -p /opt/legion-vm-tests
cp control/test/{deb_test.py,portable_session_test.py,distro_test_support.py,desktop_test_support.py} /opt/legion-vm-tests/
python3 /opt/legion-vm-tests/deb_test.py /root/deb-release
dpkg-query -W systemd libc6 libgtk-3-0 libglib2.0-0 libpolkit-gobject-1-0 > /home/approved/deb-versions.txt
cp /root/deb-release/legion-frontend-*.json /home/approved/deb-release-manifest.json
cp /etc/os-release /home/approved/deb-os-release
tar -czf /root/deb-qualification.tar.gz -C /home/approved \
  deb-versions.txt deb-gui.log deb-release-manifest.json deb-os-release deb-checks.json
