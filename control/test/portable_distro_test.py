"""Exercise the production helper against Ubuntu's systemd and Polkit."""

from datetime import timedelta
from pathlib import Path
import shlex

import portable_session_test as session
from distro_test_support import LocalMachine, persistent_files

machine = LocalMachine()
session.machine = machine
PortableSession = session.PortableSession
portable_as_user = session.portable_as_user

marker = Path("/etc/legion-control-lifecycle-test-vm")
assert marker.stat().st_uid == 0 and marker.read_text() == "legion-control-disposable-lifecycle-vm\n"
assert machine.succeed("systemd-detect-virt --vm").strip() in ["qemu", "kvm"]
launcher = "/home/approved/legion-portable-control"


def collected():
    machine.wait_until_succeeds(
        "test -z \"$(systemctl list-units --all --plain --no-legend 'legion-portable-control-*')\"",
        timeout=timedelta(seconds=15),
    )


before = persistent_files()
print("Checking root and unsealed entry-point rejection", flush=True)
machine.fail(shlex.quote(launcher) + " --control")
machine.fail(shlex.quote(launcher) + " --cleanup")
machine.fail(portable_as_user("approved", shlex.quote(launcher) + " --cleanup"))

print("Checking approved startup, command validation, synthetic write/readback/restore", flush=True)
app = PortableSession("approved", launcher)
assert app.cli == "/usr/local/bin/legion_cli", app.cli
app.prepare("success")
app.send("connect")
app.send("enable", "org.freedesktop.DBus.Error.AccessDenied")
app.send("authorize")
app.send("invalid", "org.freedesktop.DBus.Error.InvalidArgs")
app.send("persistent", "io.github.prnice.LegionControl1.Error.NotSupported")
app.send("enable")
assert app.value("battery-conservation") == "enabled\n"
app.send("disable")
assert app.value("battery-conservation") == "disabled\n"
app.send("fan")
assert app.value("payload-read") == "synthetic fan data\n"
app.close()
collected()

print("Checking denial and missing authentication agent", flush=True)
for user in ["denied", "challenge"]:
    output = "/home/" + user + "/production.out"
    user_launcher = "/home/" + user + "/legion-portable-control"
    machine.fail(portable_as_user(user, shlex.quote(user_launcher) + " --control") + " >" + output + " 2>" + output + ".err")
    assert "CONTROL_READY " not in machine.succeed("cat " + output)
    error = Path(output + ".err").read_text()
    assert "GDBus.Error:" in error, error
    collected()

print("Checking failed, incomplete, flooding, and stalled CLI startup", flush=True)
for mode in ["missing", "fail", "flood", "hang"]:
    Path("/run/legion-cli-help-mode").write_text(mode + "\n")
    try:
        output = "/home/approved/production.out"
        machine.fail(portable_as_user("approved", shlex.quote(launcher) + " --control") + " >" + output + " 2>" + output + ".err")
        text = Path(output).read_text()
        assert "CONTROL_SETUP_ERROR " in text and "CONTROL_READY " not in text, text
        collected()
    finally:
        Path("/run/legion-cli-help-mode").unlink()

print("Checking crash containment and shared write lock", flush=True)
first = PortableSession("approved", launcher)
first.prepare("tree")
first.send("connect")
first.send("authorize")
first.begin("enable")
pids = first.wait_tree()
second = PortableSession("approved", launcher)
second.prepare("success")
second.send("connect")
second.send("authorize")
second.send("enable", "io.github.prnice.LegionControl1.Error.Busy")
machine.succeed("kill -KILL " + str(first.helper))
machine.fail("flock -n /run/legion-control/operation.lock true")
for pid in pids:
    machine.wait_until_succeeds("test ! -e /proc/" + str(pid), timeout=timedelta(seconds=8))
machine.wait_until_succeeds("flock -n /run/legion-control/operation.lock true", timeout=timedelta(seconds=8))
second.send("enable")
second.send("disable")
second.close()
first.close()
collected()
assert persistent_files() == before, "Portable use changed persistent integration files"
print("PASS: Ubuntu production helper qualification with synthetic hardware", flush=True)
