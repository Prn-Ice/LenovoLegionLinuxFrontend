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
apt-get install -y --no-install-recommends policykit-1 dbus jq util-linux \
  libgtk-3-0 libgl1-mesa-dri libglx-mesa0 libegl1 libegl-mesa0 libgles2 \
  gsettings-desktop-schemas xvfb xauth xdotool desktop-file-utils appstream \
  imagemagick tesseract-ocr
printf 'legion-control-disposable-lifecycle-vm\n' > /etc/legion-control-lifecycle-test-vm
chmod 644 /etc/legion-control-lifecycle-test-vm
for user in approved denied challenge; do useradd -m -s /bin/bash "$user"; done
# Preserve available GUI evidence even when a package check fails.
# shellcheck source=control/test/deb_evidence.sh
source control/test/deb_evidence.sh
finish_qualification() {
  local qualification_status=$? evidence_status=0
  trap - EXIT
  retain_deb_evidence /home/approved /root/deb-qualification.tar.gz "$qualification_status" || evidence_status=$?
  exit "$evidence_status"
}
trap finish_qualification EXIT
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
manifests=(/root/deb-release/legion-frontend-*.json)
fixtures=/root/deb-release/vm-fixtures.tar.gz
[[ $(sha256sum "$fixtures" | cut -d' ' -f1) == "$(jq -r .vm_fixtures_sha256 "${manifests[0]}")" ]]
diff <(printf '%s\n' legion-helper-test-client legion_cli) <(tar -tzf "$fixtures" | sort -u)
# Refuse links, directories, and other archive entries before extracting bytes.
tar -tvzf "$fixtures" | awk 'substr($0,1,1) != "-" { exit 1 }'
for name in legion_cli legion-helper-test-client; do
  tar -xOzf "$fixtures" "$name" >/tmp/fixtures/"$name"
  chmod 755 /tmp/fixtures/"$name"
done
install -m755 /tmp/fixtures/legion_cli /usr/local/bin/legion_cli
install -m755 /tmp/fixtures/legion-helper-test-client /usr/local/bin/legion-helper-test-client
systemctl restart polkit.service
mkdir -p /opt/legion-vm-tests
cp control/test/{deb_test.sh,helper_session_test.sh,distro_test_support.sh,desktop_test_support.sh} /opt/legion-vm-tests/
bash /opt/legion-vm-tests/deb_test.sh /root/deb-release
dpkg-query -W systemd libc6 libgtk-3-0 libglib2.0-0 libpolkit-gobject-1-0 > /home/approved/deb-versions.txt
cp /root/deb-release/legion-frontend-*.json /home/approved/deb-release-manifest.json
cp /etc/os-release /home/approved/deb-os-release
