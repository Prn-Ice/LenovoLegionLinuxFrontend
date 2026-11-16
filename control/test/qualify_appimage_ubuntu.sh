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
cp control/test/{appimage_test.py,portable_session_test.py,distro_test_support.py,desktop_test_support.py} /opt/legion-vm-tests/
apt-get install -y --no-install-recommends gdb systemd-coredump at-spi2-core \
  mesa-utils python3-xlib x11-utils openbox wmctrl
if ldconfig -p | grep 'libgtk-3.so.0' > /dev/null; then
  echo 'Diagnostic prerequisites must not supply host GTK 3.' >&2
  exit 1
fi
cp control/test/{appimage_diagnostic.py,appimage_close_observer.py,appimage_gtk_fixture.py} /opt/legion-vm-tests/
approved_uid="$(id -u approved)"
install -d -m 700 -o approved -g approved "/run/user/$approved_uid"
install -d /opt/appimage-gtk-fixture
images=(/home/approved/'AppImage with spaces/'*.AppImage)
(cd /opt/appimage-gtk-fixture && "${images[0]}" --appimage-extract >/dev/null)
bash control/test/appimage_core_diagnostic.sh prepare /root/appimage-core-diagnostic
python3 /opt/legion-vm-tests/appimage_test.py /home/approved/'AppImage with spaces'
