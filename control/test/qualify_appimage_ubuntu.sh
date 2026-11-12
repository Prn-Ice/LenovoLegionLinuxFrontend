#!/usr/bin/env bash
# All provisioning and privileged fixture commands stay inside the test VM.
set -euo pipefail
bash control/test/qualify_ubuntu.sh
export DEBIAN_FRONTEND=noninteractive
apt-get install -y --no-install-recommends libgl1-mesa-dri \
  libglx-mesa0 libegl1 libegl-mesa0 libgles2 xvfb xauth xdotool fuse3
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
python3 /opt/legion-vm-tests/appimage_test.py /home/approved/'AppImage with spaces'
dpkg-query -W fuse3 libgl1-mesa-dri libegl1 libegl-mesa0 libgles2 > /home/approved/appimage-versions.txt
cp /home/approved/'AppImage with spaces'/legion-frontend-*.json /home/approved/appimage-release-manifest.json
tar -czf /root/appimage-qualification.tar.gz -C /home/approved \
  appimage-versions.txt appimage-gui-fuse.log appimage-gui-extracted.log \
  appimage-runtime-fuse.txt appimage-runtime-extracted.txt appimage-release-manifest.json
