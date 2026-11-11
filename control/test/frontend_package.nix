{ pkgs, frontend }:

let
  fixtures = pkgs.callPackage ./fixtures.nix { };
  bundle = "${frontend}/app/legion-linux-frontend";
in
pkgs.testers.runNixOSTest {
  name = "legion-frontend-package";
  nodes.machine = {
    security.polkit.enable = true;
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.systemd1.manage-units" && subject.user == "approved") {
          return polkit.Result.YES;
        }
      });
    '';
    users.users.approved = {
      isNormalUser = true;
      uid = 1000;
    };
    environment.etc."legion-control-lifecycle-test-vm".text =
      "legion-control-disposable-lifecycle-vm\n";
    environment.systemPackages = [
      frontend
      fixtures
      pkgs.util-linux
      pkgs.xvfb-run
      pkgs.xdotool
    ];
    hardware.graphics.enable = true;
    virtualisation.memorySize = 2048;
    virtualisation.cores = 2;
  };
  testScript = builtins.readFile ./portable_session_test.py + ''
    start_all()
    machine.wait_for_unit("polkit.service")

    with subtest("installation includes desktop metadata and leaves services disabled"):
        machine.succeed("test -f ${frontend}/share/applications/io.github.prnice.legion_linux_frontend.desktop")
        machine.succeed("test -f ${frontend}/share/metainfo/io.github.prnice.legion_linux_frontend.metainfo.xml")
        machine.succeed("test -f ${bundle}/share/licenses/legion_frontend/THIRD_PARTY_NOTICES.md")
        machine.succeed("test -x ${bundle}/libexec/legion-portable-control")
        machine.succeed("test ! -d ${bundle}/lib/systemd; test ! -d ${bundle}/share/polkit-1; test ! -d ${bundle}/share/dbus-1")
        machine.fail("systemctl cat legion-control.service")
        machine.fail("systemctl cat legion-telemetry.service")

    with subtest("the public launcher renders a Flutter frame"):
        command = "xvfb-run -a -s '-screen 0 1280x800x24' sh -c " + shlex.quote(
            "export LIBGL_ALWAYS_SOFTWARE=1 GSETTINGS_BACKEND=memory; "
            "dbus-run-session -- legion_frontend >/home/approved/gui.log 2>&1 & "
            "app=$!; trap 'kill $app 2>/dev/null || true' EXIT; "
            "xdotool search --sync --onlyvisible --class io.github.prnice.legion_linux_frontend "
            ">/home/approved/window.id; "
            "xdotool getwindowpid $(head -n1 /home/approved/window.id) >/home/approved/app.pid; wait $app"
        )
        machine.succeed(portable_as_user("approved", command) + " >/home/approved/display.log 2>&1 &")
        try:
            machine.wait_until_succeeds("test -s /home/approved/app.pid", timeout=timedelta(seconds=60))
        except Exception:
            print(machine.succeed("cat /home/approved/gui.log /home/approved/display.log"))
            raise
        pid = int(machine.succeed("cat /home/approved/app.pid").strip())
        executable = machine.succeed("readlink -f /proc/" + str(pid) + "/exe").strip()
        assert executable.startswith("${bundle}/"), executable
        machine.succeed("test -x " + shlex.quote(executable.rsplit("/", 1)[0] + "/libexec/legion-portable-control"))
        machine.succeed("kill " + str(pid))

    with subtest("the installed helper performs synthetic write, readback, restore, and cleanup"):
        app = PortableSession("approved", "${bundle}/libexec/legion-portable-control", copy_launcher=False)
        expected_cli = machine.succeed("readlink -f /run/current-system/sw/bin/legion_cli").strip()
        assert app.cli == expected_cli, (app.cli, expected_cli)
        app.prepare("success")
        app.send("connect")
        app.send("authorize")
        app.send("enable")
        assert app.value("battery-conservation") == "enabled\n"
        app.send("disable")
        assert app.value("battery-conservation") == "disabled\n"
        app.close()
        machine.wait_until_succeeds("test -z \"$(systemctl list-units --all --plain --no-legend 'legion-portable-control-*')\"", timeout=timedelta(seconds=8))
  '';
}
