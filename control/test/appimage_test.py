"""Check release launch and the bundled helper from FUSE and extraction."""

import hashlib
import json
import os
import shlex
import subprocess
import sys
from datetime import timedelta
from pathlib import Path

import portable_session_test as session
from desktop_test_support import gui, stop
from distro_test_support import LocalMachine, persistent_files

if len(sys.argv) == 4 and sys.argv[1] == "--gui":
    gui(
        sys.argv[2],
        "appimage-gui-" + sys.argv[3] + ".log",
        sys.argv[3],
        bundled_libraries=True,
    )
    sys.exit(0)

marker = Path("/etc/legion-control-lifecycle-test-vm")
assert os.getuid() == 0 and marker.stat().st_uid == 0
assert marker.read_text() == "legion-control-disposable-lifecycle-vm\n"
machine = LocalMachine()
assert machine.succeed("systemd-detect-virt --vm").strip() in ["kvm", "qemu"]
session.machine = machine
directory = Path(sys.argv[1])
machine.succeed(
    "cd " + shlex.quote(str(directory)) + " && sha256sum --check SHA256SUMS"
)
image = next(directory.glob("*.AppImage"))
manifest = json.loads(next(directory.glob("legion-frontend-*.json")).read_text())
assert (
    manifest["portable_control"]
    and manifest["default_control_mode"] == "installedService"
)
assert manifest["host_executables"] == ["/bin/sh", "dirname", "mktemp", "rm"]
assert manifest["native_runtime"]["helper"]["linkage"] == "static"
assert "libgtk-3.so.0" not in machine.succeed("ldconfig -p")
print("ARTIFACT_SHA256 " + manifest["files"][image.name] + " " + image.name, flush=True)
assert not Path("/usr/lib/jvm").exists(), "The acceptance VM must not supply a JVM"
before = persistent_files()


def check_helper(appdir):
    helper = str(appdir) + "/usr/lib/legion_frontend/libexec/legion-portable-control"
    elf = machine.succeed(
        session.portable_as_user("approved", "readelf -lW -dW " + shlex.quote(helper))
    )
    assert "INTERP" not in elf and "(NEEDED)" not in elf, elf
    documents = machine.succeed(
        session.portable_as_user(
            "approved", shlex.quote(str(appdir / "usr/bin/xdg-user-dir")) + " DOCUMENTS"
        )
    ).strip()
    assert documents.startswith("/home/approved"), documents
    digest = machine.succeed(
        session.portable_as_user("approved", "sha256sum " + shlex.quote(helper))
    ).split()[0]
    assert (
        digest
        == manifest["appdir"][
            "./usr/lib/legion_frontend/libexec/legion-portable-control"
        ]["sha256"]
    )
    app = session.PortableSession("approved", helper, copy_launcher=False)
    assert app.cli == "/usr/local/bin/legion_cli", app.cli
    app.prepare("success")
    app.send("connect")
    app.send("authorize")
    app.send("enable")
    assert app.value("battery-conservation") == "enabled\n"
    app.send("disable")
    assert app.value("battery-conservation") == "disabled\n"
    maps = machine.succeed("cat /proc/" + str(app.helper) + "/maps")
    assert ".so" not in maps, "The static helper loaded a shared library:\n" + maps
    app.close()
    machine.wait_until_succeeds(
        "test -z \"$(systemctl list-units --all --plain --no-legend 'legion-portable-control-*')\"",
        timeout=timedelta(seconds=15),
    )


mount_output = Path("/home/approved/appimage-mount.out")
with (
    mount_output.open("w") as output,
    Path("/home/approved/appimage-mount.err").open("w") as error,
):
    mount = subprocess.Popen(
        ["runuser", "-u", "approved", "--", str(image), "--appimage-mount"],
        stdout=output,
        stderr=error,
        start_new_session=True,
    )
    try:
        machine.wait_until_succeeds(
            "grep '^/tmp/.mount_' " + str(mount_output), timeout=timedelta(seconds=15)
        )
        mountpoint = Path(mount_output.read_text().splitlines()[0])
        assert str(mountpoint).startswith("/tmp/.mount_")
        check_helper(mountpoint)
        print(
            "PASS: bundled helper from FUSE with synthetic write/readback/restore",
            flush=True,
        )
    finally:
        stop(mount)

machine.succeed(
    "runuser -u approved -- xvfb-run -a python3 /opt/legion-vm-tests/appimage_test.py --gui "
    + shlex.quote(str(image))
    + " fuse"
)
extraction = Path("/home/approved/Extracted app with spaces")
machine.succeed(
    session.portable_as_user(
        "approved",
        "mkdir -p "
        + shlex.quote(str(extraction))
        + "; cd "
        + shlex.quote(str(extraction))
        + "; "
        + shlex.quote(str(image))
        + " --appimage-extract >/dev/null",
    )
)
appdir = extraction / "squashfs-root"
cleanup = manifest["native_runtime"]["helper"]["cleanup"]
helper_bytes = (
    appdir / "usr/lib/legion_frontend/libexec/legion-portable-control"
).read_bytes()
offset = helper_bytes.find(b"\x7fELF", 1)
cleanup_bytes = None
while offset >= 0:
    candidate = helper_bytes[offset : offset + cleanup["size"]]
    if hashlib.sha256(candidate).hexdigest() == cleanup["sha256"]:
        cleanup_bytes = candidate
        break
    offset = helper_bytes.find(b"\x7fELF", offset + 1)
assert cleanup_bytes is not None, (
    "The recorded cleanup ELF is not embedded in the helper"
)
unsealed = Path("/tmp/legion-unsealed-cleanup")
unsealed.write_bytes(cleanup_bytes)
unsealed.chmod(0o555)
try:
    for command in (
        [str(unsealed)],
        ["runuser", "-u", "approved", "--", str(unsealed)],
    ):
        result = subprocess.run(
            command, capture_output=True, text=True, check=False, timeout=5
        )
        assert result.returncode == 2 and not result.stdout, result
finally:
    unsealed.unlink()
check_helper(appdir)
print(
    "PASS: bundled helper from extraction with synthetic write/readback/restore",
    flush=True,
)
machine.succeed(
    "runuser -u approved -- xvfb-run -a python3 /opt/legion-vm-tests/appimage_test.py --gui "
    + shlex.quote(str(appdir / "AppRun"))
    + " extracted"
)
machine.wait_until_succeeds(
    'test -z "$(findmnt -rn -t fuse,fuse.squashfuse)"', timeout=timedelta(seconds=10)
)
assert persistent_files() == before, "AppImage use changed persistent integration files"
print(
    "PASS: AppImage FUSE/extraction qualification; persistent integration files unchanged",
    flush=True,
)
