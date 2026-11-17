#!/usr/bin/env bash
# All provisioning and privileged fixture commands stay inside the test VM.
set -euo pipefail
bash control/test/qualify_ubuntu.sh
# shellcheck source=control/test/appimage_evidence.sh
source control/test/appimage_evidence.sh
finish_qualification() {
  local status=$?
  trap - EXIT
  local evidence_status=0
  retain_appimage_evidence /home/approved /root/appimage-qualification.tar.gz "$status" \
    || evidence_status=$?
  exit "$evidence_status"
}
trap finish_qualification EXIT
export DEBIAN_FRONTEND=noninteractive
apt-get install -y --no-install-recommends libgl1-mesa-dri \
  libglx-mesa0 libegl1 libegl-mesa0 libgles2 xvfb xauth xdotool fuse3 \
  imagemagick tesseract-ocr
if ldconfig -p | grep 'libgtk-3.so.0' > /dev/null; then
  echo 'The acceptance VM must not supply GTK 3.' >&2
  exit 1
fi
modprobe fuse
test -c /dev/fuse
mkdir -p /home/approved/'AppImage with spaces'
tar -xzf /root/appimage-release.tar.gz -C /home/approved/'AppImage with spaces'
chown -R approved:approved /home/approved/'AppImage with spaces'
mkdir -p /opt/legion-vm-tests
cp control/test/{appimage_test.sh,portable_session_test.sh,distro_test_support.sh,desktop_test_support.sh} /opt/legion-vm-tests/
bash /opt/legion-vm-tests/appimage_test.sh /home/approved/'AppImage with spaces'
