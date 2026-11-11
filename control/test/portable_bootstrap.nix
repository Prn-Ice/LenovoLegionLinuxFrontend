{ pkgs }:

let
  fixtures = pkgs.callPackage ./fixtures.nix { };
  probe = pkgs.callPackage ./bootstrap-package.nix { inherit fixtures; };
in
pkgs.testers.runNixOSTest {
  name = "legion-portable-bootstrap";
  nodes.machine = {
    security.polkit.enable = true;
    users.users = {
      approved = {
        isNormalUser = true;
        uid = 1000;
      };
      denied = {
        isNormalUser = true;
        uid = 1001;
      };
      challenge = {
        isNormalUser = true;
        uid = 1002;
      };
    };
    # Deterministic policy exists only in this disposable VM. The production
    # host keeps its own systemd policy and desktop authentication agent.
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id != "org.freedesktop.systemd1.manage-units") return;
        if (subject.user == "approved") return polkit.Result.YES;
        if (subject.user == "denied") return polkit.Result.NO;
        if (subject.user == "challenge") return polkit.Result.AUTH_ADMIN;
      });
    '';
    environment.etc."legion-control-lifecycle-test-vm".text =
      "legion-control-disposable-lifecycle-vm\n";
    environment.systemPackages = [
      probe
      fixtures
      pkgs.util-linux
    ];
    systemd.services.legion-bootstrap-gate.serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "legion-bootstrap-test-gate" ''
        trap 'exit 0' USR1
        ${pkgs.coreutils}/bin/sleep 30 &
        wait
      '';
      TimeoutStartSec = 35;
    };
    virtualisation.memorySize = 1024;
  };
  testScript = builtins.readFile ./portable_session_test.py + ''
    start_all()
    machine.wait_for_unit("polkit.service")
    snapshot_checks = machine.succeed("runuser -u approved -- executable-snapshot-test")
    assert "# SKIP" not in snapshot_checks, snapshot_checks
    machine.succeed("runuser -u approved -- portable-lifetime-test")

    def as_user(user, command):
        return "runuser -u " + shlex.quote(user) + " -- sh -c " + shlex.quote(command)

    def stage(user):
        directory = "/home/" + user + "/AppImage with spaces"
        machine.succeed(as_user(user, "mkdir -p " + shlex.quote(directory)))
        binary = directory + "/portable-bootstrap-probe"
        machine.succeed(as_user(user, "rm -f " + shlex.quote(binary) + "; cp ${probe}/bin/portable-bootstrap-probe " + shlex.quote(binary) + "; chmod 700 " + shlex.quote(binary)))
        return binary

    def launch(user="approved", option="", gated=False):
        binary = stage(user)
        output = "/home/" + user + "/bootstrap.out"
        fifo = "/home/" + user + "/bootstrap.in"
        if gated:
            machine.succeed(as_user(user, "rm -f " + fifo + "; mkfifo " + fifo))
        command = "export LD_LIBRARY_PATH=/nonexistent/appimage/lib GIO_EXTRA_MODULES=/nonexistent/appimage/modules DBUS_SYSTEM_BUS_ADDRESS=unix:path=/nonexistent/appimage/bus; exec " + shlex.quote(binary) + " " + option
        if gated:
            command += " <>" + fifo
        machine.succeed(as_user(user, command) + " >" + output + " 2>" + output + ".err &")
        machine.wait_until_succeeds("grep SNAPSHOT_READY " + output, timeout=timedelta(seconds=10))
        ready = machine.succeed("cat " + output)
        pid_match = re.search(r"launcher=(\d+)", ready)
        unit_match = re.search(r"unit=(\S+)", ready)
        assert pid_match and unit_match, ready
        pid = int(pid_match.group(1))
        unit = unit_match.group(1)
        return pid, unit, output, binary, fifo

    def wait_collected():
        try:
            machine.wait_until_succeeds("test -z \"$(systemctl list-units --all --plain --no-legend 'legion-bootstrap-probe-*')\"", timeout=timedelta(seconds=8))
        except Exception:
            print(machine.succeed("systemctl list-units --all --no-pager 'legion-bootstrap-probe-*'; systemctl list-jobs --no-pager; journalctl -b --no-pager -n 60"))
            raise

    def root_helper(output):
        try:
            machine.wait_until_succeeds("grep 'ROOT_HELPER uid=0' " + output, timeout=timedelta(seconds=10))
        except Exception:
            print(machine.succeed("cat " + output + " " + output + ".err; journalctl -b --no-pager -n 60"))
            raise
        text = machine.succeed("cat " + output)
        assert "sealed=yes" in text, text
        match = re.search(r"ROOT_HELPER uid=0 pid=(\d+)", text)
        assert match, text
        return int(match.group(1))

    with subtest("authorized startup from a user-owned path containing spaces"):
        pid, unit, output, _, _ = launch()
        helper = root_helper(output)
        executable = machine.succeed("systemctl show --property=ExecStart --value " + unit)
        assert "/proc/self/fd/0" in executable, executable
        assert "/proc/" + str(pid) + "/fd/" not in executable, executable
        machine.fail(as_user("approved", "ls /proc/" + str(pid) + "/fd"))
        machine.succeed("test -e /proc/" + str(helper))
        machine.succeed("kill -TERM " + str(pid))
        machine.wait_until_succeeds("test ! -e /proc/" + str(helper), timeout=timedelta(seconds=5))
        wait_collected()

    with subtest("app-parent death ends the launcher and root helper"):
        pid, unit, output, _, _ = launch()
        helper = root_helper(output)
        parent = int(machine.succeed("awk '{print $4}' /proc/" + str(pid) + "/stat").strip())
        assert parent > 1, parent
        machine.succeed("kill -KILL " + str(parent))
        machine.wait_until_succeeds("test ! -e /proc/" + str(helper), timeout=timedelta(seconds=5))
        wait_collected()

    with subtest("source replacement cannot change the approved snapshot"):
        pid, unit, output, binary, fifo = launch(option="--wait-before-start", gated=True)
        # Swap the downloaded path after the snapshot is sealed. The service
        # must still execute the original fixed helper, not this replacement.
        machine.succeed(as_user("approved", "mv " + shlex.quote(binary) + " " + shlex.quote(binary + ".old") + "; printf '#!/bin/sh\\nexit 99\\n' > " + shlex.quote(binary)))
        machine.succeed(as_user("approved", "printf s >" + fifo))
        helper = root_helper(output)
        machine.succeed("kill -KILL " + str(pid))
        machine.wait_until_succeeds("test ! -e /proc/" + str(helper), timeout=timedelta(seconds=5))
        wait_collected()

    with subtest("denied approval and a missing authentication agent"):
        for user in ["denied", "challenge"]:
            binary = stage(user)
            output = "/home/" + user + "/denied.out"
            machine.fail(as_user(user, shlex.quote(binary)) + " >" + output + " 2>" + output + ".err")
            assert "ROOT_HELPER" not in machine.succeed("cat " + output)
            assert machine.succeed("cat " + output + ".err").strip()
            wait_collected()

    with subtest("launcher death cancels a helper still waiting to start"):
        for signal in ["TERM", "KILL"]:
            pid, unit, output, _, _ = launch(option="--queue-behind-gate")
            machine.wait_until_succeeds("grep START_ACKNOWLEDGED " + output, timeout=timedelta(seconds=10))
            assert machine.succeed("systemctl show --property=ActiveState --value " + unit).strip() == "inactive"
            assert "ROOT_HELPER" not in machine.succeed("cat " + output)
            machine.succeed("kill -" + signal + " " + str(pid))
            wait_collected()
            machine.succeed("systemctl stop legion-bootstrap-gate.service")
            assert "ROOT_HELPER" not in machine.succeed("cat " + output)

    with subtest("a late helper refuses handles from an exited launcher"):
        pid, unit, output, _, _ = launch(option="--queue-behind-gate")
        machine.wait_until_succeeds("grep START_ACKNOWLEDGED " + output, timeout=timedelta(seconds=10))
        machine.succeed("kill -KILL " + str(pid))
        machine.succeed("systemctl kill --kill-whom=main --signal=USR1 legion-bootstrap-gate.service")
        wait_collected()
        assert "ROOT_HELPER" not in machine.succeed("cat " + output)

    with subtest("native peer connection has a deadline and supports cancellation"):
        for index, mode in enumerate(["timeout", "cancel"]):
            unit = "legion-bootstrap-probe-01234567-89ab-4cde-8fab-" + str(index).zfill(12) + ".service"
            socket = "/run/legion-stalled-peer.sock"
            output = "/tmp/stalled-peer.out"
            machine.succeed("rm -f " + socket + " " + output)
            machine.succeed("systemd-run --quiet --collect --service-type=exec --unit=" + unit + " --property=RuntimeMaxSec=15 --property=StandardOutput=append:" + output + " ${fixtures}/bin/legion-portable-test-client --stall-peer " + socket)
            machine.wait_until_succeeds("grep FAKE_READY " + output, timeout=timedelta(seconds=5))
            helper = machine.succeed("systemctl show --property=MainPID --value " + unit).strip()
            command = "legion-portable-test-client --connection-" + mode + " unix:path=" + socket + " " + unit + " " + helper
            if mode == "timeout":
                machine.succeed(portable_as_user("approved", command))
            else:
                machine.succeed(portable_as_user("approved", command) + " >/home/approved/connect.out 2>/home/approved/connect.err &")
                machine.wait_until_succeeds("grep AUTH_SEEN " + output, timeout=timedelta(seconds=4))
                text = machine.succeed("cat /home/approved/connect.out")
                pid = re.search(r"CONNECTING pid=(\d+)", text)
                assert pid, text
                machine.succeed("kill -USR1 " + pid.group(1))
                machine.wait_until_succeeds("grep CONNECTION_ENDED /home/approved/connect.out", timeout=timedelta(seconds=3))
            machine.wait_until_succeeds("grep AUTH_CLOSED " + output, timeout=timedelta(seconds=3))
            wait_collected()

    with subtest("approved root peer validates and applies typed commands"):
        app = PortableSession("approved", "${probe}/bin/portable-bootstrap-probe")
        app.prepare("success")
        machine.succeed(portable_as_user("approved", "legion-portable-test-client --fake-peer /home/approved/fake.sock") + " >/tmp/fake-peer.out 2>/tmp/fake-peer.err &")
        machine.wait_until_succeeds("grep FAKE_READY /tmp/fake-peer.out", timeout=timedelta(seconds=5))
        code, _ = machine.execute(portable_as_user("approved", "legion-portable-test-client --intrude unix:path=/home/approved/fake.sock " + app.unit + " " + str(app.helper)))
        assert code == 8, code
        machine.wait_until_succeeds("grep FAKE_CLOSED_BEFORE_AUTH /tmp/fake-peer.out", timeout=timedelta(seconds=5))
        # A different process of the same user reaches the root socket, then
        # fails EXTERNAL authentication before any methods are exported to it.
        code, _ = machine.execute(portable_as_user("approved", "legion-portable-test-client --intrude " + shlex.quote(app.address) + " " + app.unit + " " + str(app.helper)))
        assert code == 7, code
        code, _ = machine.execute(portable_as_user("denied", "legion-portable-test-client --intrude " + shlex.quote(app.address) + " " + app.unit + " " + str(app.helper)))
        assert code == 7, code
        app.send("connect")
        code, _ = machine.execute(portable_as_user("approved", "legion-portable-test-client --intrude " + shlex.quote(app.address) + " " + app.unit + " " + str(app.helper)))
        assert code == 8, code
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
        machine.succeed(app.private("test -z \"$(find /tmp -maxdepth 1 -name 'legion-control-*' -type f -print)\""))
        app.close()
        wait_collected()

    with subtest("idle private peer shuts down"):
        app = PortableSession("approved", "${probe}/bin/portable-bootstrap-probe")
        app.send("connect")
        app.send("idle")
        machine.wait_until_succeeds("test ! -e " + app.runtime, timeout=timedelta(seconds=8))
        app.close()
        wait_collected()

    with subtest("helper crash keeps other helpers blocked through backend cleanup"):
        first = PortableSession("approved", "${probe}/bin/portable-bootstrap-probe")
        first.prepare("tree")
        first.send("connect")
        first.send("authorize")
        first.begin("enable")
        pids = first.wait_tree()
        second = PortableSession("approved", "${probe}/bin/portable-bootstrap-probe")
        second.prepare("success")
        second.send("connect")
        second.send("authorize")
        second.send("enable", "io.github.prnice.LegionControl1.Error.Busy")
        machine.succeed("kill -KILL " + str(first.helper))
        # systemd still owns the input descriptor and its operation lock while
        # the synthetic descendants resist SIGTERM until SIGKILL escalation.
        machine.fail("flock -n /run/legion-control/operation.lock true")
        second.send("enable", "io.github.prnice.LegionControl1.Error.Busy")
        for pid in pids:
            machine.wait_until_succeeds("test ! -e /proc/" + str(pid), timeout=timedelta(seconds=5))
        machine.wait_until_succeeds("flock -n /run/legion-control/operation.lock true", timeout=timedelta(seconds=5))
        second.send("enable")
        second.close()
        first.close()
        wait_collected()

    machine.succeed("test ! -e /etc/systemd/system/legion-control.service; test ! -e /run/systemd/system/legion-control.service")
  '';
}
