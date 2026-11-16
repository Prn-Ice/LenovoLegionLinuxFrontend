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
  imagemagick tesseract-ocr binutils gdb systemd-coredump at-spi2-core
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
cp control/test/template_close_test.py /opt/template-tests/
bash control/test/template_core_diagnostic.sh prepare /root/template-core-diagnostic
runuser -u approved -- xvfb-run -a --server-args='-screen 0 1280x800x24' \
  dbus-run-session -- python3 /opt/template-tests/template_close_test.py
