#!/usr/bin/env bash
# Provision only the disposable Ubuntu guest, then test the untouched template.
set -euo pipefail
[[ $(id -u) == 0 && $(systemd-detect-virt --vm || true) == kvm ]]
source /etc/os-release
[[ $ID:$VERSION_ID == ubuntu:22.04 ]]
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends dbus python3 util-linux \
  libgtk-3-0 libgl1-mesa-dri libglx-mesa0 libegl1 libegl-mesa0 libgles2 \
  gsettings-desktop-schemas xvfb xauth xdotool x11-utils openbox \
  imagemagick tesseract-ocr binutils gdb systemd-coredump at-spi2-core \
  wmctrl python3-xlib python3-gi gir1.2-gtk-3.0
useradd -m -s /bin/bash approved
mkdir /root/template-release
tar -xzf /root/template-release.tar.gz -C /root/template-release
(cd /root/template-release && sha256sum --check SHA256SUMS)
install -d /opt/shutdown-template
tar -xzf /root/template-release/template-bundle.tar.gz -C /opt/shutdown-template
python3 - <<'PY'
import hashlib
import json
from pathlib import Path

root = Path('/opt/shutdown-template')
manifest = json.loads(Path('/root/template-release/template-manifest.json').read_text())
for name, digest in manifest['bundle'].items():
    assert hashlib.sha256((root / name).read_bytes()).hexdigest() == digest, name
PY
install -d /opt/template-tests
cp control/test/{template_close_test.py,template_close_observer.py,template_gtk_fixture.py} /opt/template-tests/
bash control/test/template_core_diagnostic.sh prepare /root/template-core-diagnostic
approved_uid="$(id -u approved)"
install -d -m 700 -o approved -g approved "/run/user/$approved_uid"
cd /home/approved
runuser -u approved -- env -i HOME=/home/approved USER=approved LOGNAME=approved \
  PATH=/usr/local/bin:/usr/bin:/bin LANG=C.UTF-8 XDG_RUNTIME_DIR="/run/user/$approved_uid" \
  GSETTINGS_BACKEND=memory GDK_BACKEND=x11 LIBGL_ALWAYS_SOFTWARE=1 \
  xvfb-run -a --server-args='-screen 0 1280x800x24' dbus-run-session -- \
  python3 /opt/template-tests/template_close_test.py > /home/approved/template-session.log 2>&1 &
session_pid=$!
while [[ -d /proc/$session_pid ]]; do
  if [[ -f template-hang-request.json && ! -f template-hang-collected ]]; then
    hang_pid="$(python3 -c 'import json; print(json.load(open("template-hang-request.json"))["pid"])')"
    [[ $hang_pid =~ ^[0-9]+$ ]]
    [[ $(readlink "/proc/$hang_pid/exe") == /opt/shutdown-template/shutdown_template ]]
    hang_status=0
    timeout 60 gdb -q -nx -batch -ex 'set pagination off' -ex 'set debuginfod enabled off' \
      -ex 'info threads' -ex 'thread apply all bt full' -ex 'info sharedlibrary' \
      -p "$hang_pid" > /root/template-core-diagnostic/hang-all-threads.txt 2>&1 || hang_status=$?
    echo "gdb_status=$hang_status" > /root/template-core-diagnostic/hang-gdb-status.txt
    touch template-hang-collected
  fi
  sleep 0.2
done
session_status=0
wait "$session_pid" || session_status=$?
cat template-session.log
if grep -E -- '-CRITICAL|owned by uid 0|Permission denied' template-session.log; then exit 1; fi
exit "$session_status"
