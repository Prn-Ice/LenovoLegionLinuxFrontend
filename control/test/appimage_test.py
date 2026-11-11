"""Check release launch and the bundled helper from FUSE and extraction."""
from datetime import timedelta
import json
import os
from pathlib import Path
import shlex
import signal
import subprocess
import sys
import tempfile
import time

import portable_session_test as session
from distro_test_support import LocalMachine, persistent_files


def stop(process):
    if process.poll() is None:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=5)


def gui(image, extracted):
    assert os.getuid() != 0
    log_path = Path.home() / ("appimage-gui-extracted.log" if extracted else "appimage-gui-fuse.log")
    with tempfile.TemporaryDirectory(prefix="legion-gui-", dir=Path.home()) as temporary, log_path.open("w") as log:
        environment = dict(os.environ, GSETTINGS_BACKEND="memory", GDK_BACKEND="x11",
                           LIBGL_ALWAYS_SOFTWARE="1", XDG_CONFIG_HOME=temporary + "/config",
                           XDG_DATA_HOME=temporary + "/data")
        environment.pop("JAVA_HOME", None)
        environment.pop("LD_LIBRARY_PATH", None)
        process = subprocess.Popen([image], stdout=log, stderr=log, env=environment,
                                   start_new_session=True)
        try:
            deadline = time.monotonic() + 30
            while True:
                result = subprocess.run(["xdotool", "search", "--onlyvisible", "--class",
                                         "io.github.prnice.legion_linux_frontend"],
                                        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                if result.returncode == 0 and process.poll() is None:
                    print("PASS: visible Flutter window from " + ("extraction" if extracted else "FUSE"), flush=True)
                    break
                if process.poll() is not None or time.monotonic() >= deadline:
                    raise AssertionError("AppImage window did not appear:\n" + log_path.read_text())
                time.sleep(0.1)
        finally:
            stop(process)


if len(sys.argv) == 4 and sys.argv[1] == "--gui":
    gui(sys.argv[2], sys.argv[3] == "extracted")
    sys.exit(0)

marker = Path("/etc/legion-control-lifecycle-test-vm")
assert os.getuid() == 0 and marker.stat().st_uid == 0
assert marker.read_text() == "legion-control-disposable-lifecycle-vm\n"
machine = LocalMachine()
assert machine.succeed("systemd-detect-virt --vm").strip() in ["kvm", "qemu"]
session.machine = machine
directory = Path(sys.argv[1])
machine.succeed("cd " + shlex.quote(str(directory)) + " && sha256sum --check SHA256SUMS")
image = next(directory.glob("*.AppImage"))
manifest = json.loads(next(directory.glob("legion-frontend-*.json")).read_text())
assert manifest["portable_control"] and manifest["default_control_mode"] == "installedService"
print("ARTIFACT_SHA256 " + manifest["files"][image.name] + " " + image.name, flush=True)
assert not Path("/usr/lib/jvm").exists(), "The acceptance VM must not supply a JVM"
before = persistent_files()


def check_helper(appdir):
    helper = str(appdir) + "/usr/lib/legion_frontend/libexec/legion-portable-control"
    digest = machine.succeed(session.portable_as_user("approved", "sha256sum " + shlex.quote(helper))).split()[0]
    assert digest == manifest["appdir"]["./usr/lib/legion_frontend/libexec/legion-portable-control"]["sha256"]
    app = session.PortableSession("approved", helper, copy_launcher=False)
    assert app.cli == "/usr/local/bin/legion_cli", app.cli
    app.prepare("success")
    app.send("connect")
    app.send("authorize")
    app.send("enable")
    assert app.value("battery-conservation") == "enabled\n"
    app.send("disable")
    assert app.value("battery-conservation") == "disabled\n"
    app.close()
    machine.wait_until_succeeds("test -z \"$(systemctl list-units --all --plain --no-legend 'legion-portable-control-*')\"", timeout=timedelta(seconds=15))


mount_output = Path("/home/approved/appimage-mount.out")
with mount_output.open("w") as output, Path("/home/approved/appimage-mount.err").open("w") as error:
    mount = subprocess.Popen(["runuser", "-u", "approved", "--", str(image), "--appimage-mount"],
                             stdout=output, stderr=error, start_new_session=True)
    try:
        machine.wait_until_succeeds("grep '^/tmp/.mount_' " + str(mount_output), timeout=timedelta(seconds=15))
        mountpoint = Path(mount_output.read_text().splitlines()[0])
        assert str(mountpoint).startswith("/tmp/.mount_")
        check_helper(mountpoint)
        print("PASS: bundled helper from FUSE with synthetic write/readback/restore", flush=True)
    finally:
        stop(mount)

machine.succeed("runuser -u approved -- xvfb-run -a python3 /opt/legion-vm-tests/appimage_test.py --gui " + shlex.quote(str(image)) + " fuse")
extraction = Path("/home/approved/Extracted app with spaces")
machine.succeed(session.portable_as_user("approved", "mkdir -p " + shlex.quote(str(extraction)) + "; cd " + shlex.quote(str(extraction)) + "; " + shlex.quote(str(image)) + " --appimage-extract >/dev/null"))
appdir = extraction / "squashfs-root"
check_helper(appdir)
print("PASS: bundled helper from extraction with synthetic write/readback/restore", flush=True)
machine.succeed("runuser -u approved -- xvfb-run -a python3 /opt/legion-vm-tests/appimage_test.py --gui " + shlex.quote(str(appdir / "AppRun")) + " extracted")
machine.wait_until_succeeds("test -z \"$(findmnt -rn -t fuse,fuse.squashfuse)\"", timeout=timedelta(seconds=10))
assert persistent_files() == before, "AppImage use changed persistent integration files"
print("PASS: AppImage FUSE/extraction qualification; persistent integration files unchanged", flush=True)
