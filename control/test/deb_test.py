"""Install, upgrade, exercise, and purge the package inside a disposable VM."""

import hashlib
import json
import os
import shlex
import sys
from datetime import timedelta
from pathlib import Path

import portable_session_test as session
from desktop_test_support import gui
from distro_test_support import LocalMachine, persistent_files


def main():
    marker = Path("/etc/legion-control-lifecycle-test-vm")
    assert os.getuid() == 0 and marker.stat().st_uid == 0
    assert marker.read_text() == "legion-control-disposable-lifecycle-vm\n"
    machine = LocalMachine()
    assert machine.succeed("systemd-detect-virt --vm").strip() in ["kvm", "qemu"]
    session.machine = machine
    release = Path(sys.argv[1])
    machine.succeed(
        "cd " + shlex.quote(str(release)) + " && sha256sum --check SHA256SUMS"
    )
    manifest = json.loads(next(release.glob("legion-frontend-*.json")).read_text())
    package = next(release.glob("*.deb"))
    assert (
        hashlib.sha256(package.read_bytes()).hexdigest()
        == manifest["files"][package.name]
    )
    assert manifest["portable_control"] is True
    assert manifest["default_control_mode"] == "installedService"
    assert not Path("/usr/lib/jvm").exists()
    before = persistent_files()
    machine.fail("systemctl cat legion-control.service")
    machine.succeed(
        "apt-get install -y --no-install-recommends " + shlex.quote(str(package))
    )
    assert (
        machine.succeed("dpkg-query -W -f='${Version}' legion-linux-frontend").strip()
        == manifest["package_version"]
    )
    assert persistent_files() == before, (
        "Installation changed persistent integration files"
    )

    def verify_bundle():
        for name, entry in manifest["payload"].items():
            path = Path("/usr") / name.removeprefix("./")
            assert path.lstat().st_uid == 0, path
            if entry["type"] == "link":
                assert str(path.readlink()) == entry["target"], path
            else:
                assert (path.stat().st_mode & 0o777) == int(entry["mode"], 8), path
            if entry["type"] == "file":
                assert (
                    hashlib.sha256(path.read_bytes()).hexdigest() == entry["sha256"]
                ), path
        machine.succeed(
            "desktop-file-validate /usr/share/applications/io.github.prnice.legion_linux_frontend.desktop"
        )
        machine.succeed(
            "appstreamcli validate --no-net /usr/share/metainfo/io.github.prnice.legion_linux_frontend.metainfo.xml"
        )

    verify_bundle()
    machine.succeed(
        "runuser -u approved -- xvfb-run -a dbus-run-session -- python3 /opt/legion-vm-tests/deb_test.py --gui"
    )
    helper = "/usr/lib/legion_frontend/libexec/legion-portable-control"
    app = session.PortableSession("approved", helper, copy_launcher=False)
    assert app.cli == "/usr/local/bin/legion_cli", app.cli
    app.prepare("success")
    app.send("connect")
    app.send("authorize")
    app.send("resume-after-idle")
    app.send("enable")
    assert app.value("battery-conservation") == "enabled\n"
    app.send("disable")
    assert app.value("battery-conservation") == "disabled\n"
    app.close()
    for user in ["denied", "challenge"]:
        command = session.portable_as_user(user, helper + " --control")
        output = machine.fail(command)
        assert "CONTROL_READY " not in output, output
    machine.wait_until_succeeds(
        "test -z \"$(systemctl list-units --all --plain --no-legend 'legion-portable-control-*')\"",
        timeout=timedelta(seconds=15),
    )

    # Preserve an existing administrator-managed service file through upgrade
    # and purge. Its bytes and permissions form part of the snapshot.
    sentinel = Path("/etc/systemd/system/legion-control.service")
    sentinel.write_text("# Existing administrator-managed Legion service fixture\n")
    coexistence = persistent_files()
    active = session.PortableSession("approved", helper, copy_launcher=False)
    active.prepare("success")
    active.send("connect")
    active.send("authorize")
    active.send("enable")
    machine.succeed("dpkg-deb -R " + shlex.quote(str(package)) + " /tmp/upgrade")
    control = Path("/tmp/upgrade/DEBIAN/control")
    upgraded = manifest["package_version"] + "+qualification"
    control.write_text(
        control.read_text().replace(
            "Version: " + manifest["package_version"] + "\n",
            "Version: " + upgraded + "\n",
        )
    )
    machine.succeed("dpkg-deb --root-owner-group --build /tmp/upgrade /tmp/upgrade.deb")
    machine.succeed("apt-get install -y --no-install-recommends /tmp/upgrade.deb")
    assert (
        machine.succeed("dpkg-query -W -f='${Version}' legion-linux-frontend").strip()
        == upgraded
    )
    verify_bundle()
    assert active.value("battery-conservation") == "enabled\n"
    active.send("disable")
    assert active.value("battery-conservation") == "disabled\n"
    active.close()
    assert persistent_files() == coexistence, (
        "Upgrade changed existing integration files"
    )
    machine.succeed("apt-get purge -y legion-linux-frontend")
    assert not Path("/usr/lib/legion_frontend").exists()
    assert not Path("/usr/bin/legion_frontend").exists()
    assert persistent_files() == coexistence, "Purge changed existing integration files"
    session.assert_cleanup_succeeded()
    checks = {
        name: True
        for name in [
            "installation",
            "desktop",
            "helper",
            "denied",
            "missing_agent",
            "upgrade",
            "purge",
            "existing_integration_preserved",
        ]
    }
    Path("/home/approved/deb-checks.json").write_text(json.dumps(checks) + "\n")
    print(
        "PASS: Debian package install, desktop, helper, upgrade, and purge", flush=True
    )


if __name__ == "__main__":
    if sys.argv[1:] == ["--gui"]:
        gui(
            "/usr/bin/legion_frontend",
            "deb-gui.log",
            "Debian package",
            expected_executable="/usr/lib/legion_frontend/legion_frontend",
        )
    else:
        main()
