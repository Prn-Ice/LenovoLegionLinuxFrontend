{ pkgs }:

let
  probe = pkgs.stdenv.mkDerivation {
    pname = "legion-portable-bootstrap-probe";
    version = "1";
    src = pkgs.lib.fileset.toSource {
      root = ../..;
      fileset = pkgs.lib.fileset.unions [
        ../../control
        ../../telemetry
        ../../packaging
      ];
    };
    nativeBuildInputs = [
      pkgs.cmake
      pkgs.pkg-config
    ];
    buildInputs = [
      pkgs.glib
      pkgs.polkit
    ];
    preConfigure = "cd telemetry";
    cmakeFlags = [
      "-DBUILD_TESTING=ON"
      "-DBUILD_LEGION_CONTROL_SERVICE=ON"
      "-DBUILD_PORTABLE_BOOTSTRAP_PROTOTYPE=ON"
    ];
    buildPhase = ''
      runHook preBuild
      cmake --build . --target portable_bootstrap_probe executable_snapshot_test
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      install -Dm755 portable_bootstrap_probe "$out/bin/portable-bootstrap-probe"
      install -Dm755 executable_snapshot_test "$out/bin/executable-snapshot-test"
      runHook postInstall
    '';
  };
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
      pkgs.util-linux
    ];
    systemd.services.legion-bootstrap-gate.serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.coreutils}/bin/sleep 30";
      TimeoutStartSec = 35;
    };
    virtualisation.memorySize = 1024;
  };
  testScript = ''
    import re
    import shlex
    from datetime import timedelta

    start_all()
    machine.wait_for_unit("polkit.service")
    snapshot_checks = machine.succeed("runuser -u approved -- executable-snapshot-test")
    assert "# SKIP" not in snapshot_checks, snapshot_checks

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

    machine.succeed("test ! -e /etc/systemd/system/legion-control.service; test ! -e /run/systemd/system/legion-control.service")
  '';
}
