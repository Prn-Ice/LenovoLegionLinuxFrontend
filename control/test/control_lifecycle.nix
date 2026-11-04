{ pkgs }:

let
  service = pkgs.callPackage ../../telemetry/package.nix { };
  fixtures = pkgs.stdenv.mkDerivation {
    pname = "legion-control-vm-fixtures";
    version = "1";
    src = pkgs.lib.fileset.toSource {
      root = ./.;
      fileset = pkgs.lib.fileset.unions [
        ./CMakeLists.txt
        ./test_vm_guard.h
        ./control_lifecycle_fixture.cc
        ./control_lifecycle_client.cc
      ];
    };
    nativeBuildInputs = [
      pkgs.cmake
      pkgs.pkg-config
    ];
    buildInputs = [ pkgs.glib ];
  };
in
pkgs.testers.runNixOSTest {
  name = "legion-control-lifecycle";

  nodes.machine = {
    imports = [ ../../packaging/nixos/legion-telemetry.nix ];
    services.legionControl = {
      enable = true;
      package = service;
      backendPackage = fixtures;
      nextBootGraphics = true;
      reconcileGraphicsAtBoot = true;
      reconcileGraphicsAfterHibernate = false;
    };
    # Exercise the real next-boot request helper without running a boot-time
    # graphics transition or loading a hardware driver in this fixture VM.
    systemd.services.legion-graphics-reconcile.enable = false;
    boot.kernelModules = pkgs.lib.mkForce [ ];
    environment.etc."legion-control-lifecycle-test-vm".text =
      "legion-control-disposable-lifecycle-vm\n";
    environment.systemPackages = [
      fixtures
      pkgs.util-linux
      pkgs.procps
    ];
    # The test client is root inside this hardware-free VM. Keep authorization
    # deterministic while still exercising the service's real Authorize method.
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == "io.github.prnice.legion-control.manage" && subject.user == "root") {
          return polkit.Result.YES;
        }
      });
    '';
    virtualisation.memorySize = 1024;
  };

  testScript = ''
    import json
    import shlex
    from datetime import timedelta

    start_all()
    machine.wait_for_unit("legion-control.service")

    def private(command):
        pid = machine.succeed("systemctl show --property=MainPID --value legion-control.service").strip()
        assert int(pid) > 0
        return "nsenter --target " + pid + " --mount -- sh -c " + shlex.quote(command)

    def prepare(mode):
        machine.succeed(private("mkdir -p /tmp/legion-fixture; rm -f /tmp/legion-fixture/ready /tmp/legion-fixture/pids /tmp/legion-fixture/payload-read; printf '%s\\n' " + shlex.quote(mode) + " > /tmp/legion-fixture/mode"))

    def wait_collected():
        machine.wait_until_succeeds("test -z \"$(systemctl list-units --all --plain --no-legend 'legion-control-op-*.service')\"", timeout=timedelta(seconds=30))

    def start_client(operation="toggle"):
        return int(machine.succeed("legion-control-test-client " + shlex.quote(operation) + " >/tmp/control-client.out 2>/tmp/control-client.err & echo $!").strip())

    def wait_tree():
        machine.wait_until_succeeds(private("test -f /tmp/legion-fixture/ready"), timeout=timedelta(seconds=15))
        pids = [int(pid) for pid in machine.succeed(private("cat /tmp/legion-fixture/pids")).split()]
        assert len(pids) == 3, pids
        return pids

    def assert_gone(pids):
        for pid in pids:
            machine.wait_until_succeeds("test ! -e /proc/" + str(pid), timeout=timedelta(seconds=15))

    with subtest("normal completion and private temporary payload"):
        prepare("success")
        machine.succeed("legion-control-test-client toggle")
        machine.succeed("legion-control-test-client fan")
        assert machine.succeed(private("cat /tmp/legion-fixture/payload-read")) == "synthetic fan data\n"
        machine.succeed(private("test -z \"$(find /tmp -maxdepth 1 -name 'legion-control-*' -type f -print)\""))
        wait_collected()

    with subtest("next-boot graphics requests keep their private persistent state"):
        pending = json.loads(machine.succeed("legion-control-test-client boot-request"))
        assert pending["phase"] == "pending", pending
        assert pending["mode"] == "hybrid-igpu-only", pending
        stored = json.loads(machine.succeed("cat /var/lib/legion-graphics-boot/request.json"))
        assert stored == pending, stored
        assert machine.succeed("stat -c '%u:%a' /var/lib/legion-graphics-boot").strip() == "0:700"
        assert json.loads(machine.succeed("legion-control-test-client boot-status")) == pending
        cancelled = json.loads(machine.succeed("legion-control-test-client boot-cancel"))
        assert cancelled["phase"] == "cancelled", cancelled
        assert json.loads(machine.succeed("legion-control-test-client boot-status")) == cancelled
        wait_collected()

    with subtest("graphics exit classifications survive managed execution"):
        for mode, error in [("graphics-blocked", "Error.GraphicsBlocked"), ("graphics-pending", "Error.GraphicsPending")]:
            prepare(mode)
            machine.fail("legion-control-test-client graphics >/tmp/control-client.out 2>/tmp/control-client.err")
            reply = machine.succeed("cat /tmp/control-client.err")
            assert error in reply, reply
            wait_collected()

    with subtest("normal parent exit cleans detached stdout holders"):
        prepare("orphan-stdout")
        machine.succeed("legion-control-test-client toggle")
        pids = wait_tree()
        assert_gone(pids)
        wait_collected()

    with subtest("output limit stops detached descendants"):
        prepare("flood")
        machine.fail("legion-control-test-client toggle >/tmp/control-client.out 2>/tmp/control-client.err")
        reply = machine.succeed("cat /tmp/control-client.err")
        assert "Error.CommandFailed" in reply, reply
        assert_gone(wait_tree())
        wait_collected()

    with subtest("runtime deadline stops the entire backend cgroup"):
        prepare("tree")
        machine.fail("legion-control-test-client toggle >/tmp/control-client.out 2>/tmp/control-client.err")
        reply = machine.succeed("cat /tmp/control-client.err")
        assert "Error.Timeout" in reply, reply
        assert_gone(wait_tree())
        wait_collected()

    with subtest("client SIGKILL cancels the active operation"):
        prepare("tree")
        client = start_client()
        pids = wait_tree()
        machine.fail("legion-control-test-client toggle >/tmp/busy.out 2>/tmp/busy.err")
        reply = machine.succeed("cat /tmp/busy.err")
        assert "Error.Busy" in reply, reply
        machine.succeed("kill -KILL " + str(client))
        assert_gone(pids)
        wait_collected()
        prepare("success")
        machine.succeed("legion-control-test-client toggle")

    with subtest("cancelled fan operation removes its temporary payload"):
        prepare("tree")
        client = start_client("fan")
        pids = wait_tree()
        machine.succeed(private("test -n \"$(find /tmp -maxdepth 1 -name 'legion-control-*' -type f -print)\""))
        machine.succeed("kill -KILL " + str(client))
        assert_gone(pids)
        wait_collected()
        machine.succeed(private("test -z \"$(find /tmp -maxdepth 1 -name 'legion-control-*' -type f -print)\""))

    with subtest("helper SIGKILL stops its bound operation"):
        prepare("tree")
        start_client()
        pids = wait_tree()
        machine.succeed("systemctl kill --kill-whom=main --signal=KILL legion-control.service")
        assert_gone(pids)
        wait_collected()
        machine.wait_until_succeeds("systemctl is-active legion-control.service", timeout=timedelta(seconds=15))
        prepare("success")
        machine.succeed("legion-control-test-client toggle")
        wait_collected()

    machine.succeed("systemctl is-active legion-control.service")
  '';
}
