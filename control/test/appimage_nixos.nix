{
  pkgs,
  image,
}:
let
  fixtures = pkgs.callPackage ./fixtures.nix { };
in
pkgs.testers.runNixOSTest {
  name = "legion-appimage-nixos";
  nodes.machine = {
    security.polkit.enable = true;
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id != "org.freedesktop.systemd1.manage-units") return;
        if (subject.user == "approved") return polkit.Result.YES;
        if (subject.user == "denied") return polkit.Result.NO;
        if (subject.user == "challenge") return polkit.Result.AUTH_ADMIN;
      });
    '';
    users.users.approved = {
      isNormalUser = true;
      uid = 1000;
    };
    users.users.denied.isNormalUser = true;
    users.users.challenge.isNormalUser = true;
    programs.fuse.enable = true;
    programs.nix-ld = {
      enable = true;
      libraries = with pkgs; [
        libglvnd
        libx11
        libxcb
        wayland
      ];
    };
    environment.etc."legion-control-lifecycle-test-vm".text =
      "legion-control-disposable-lifecycle-vm\n";
    environment.systemPackages = [
      fixtures
      pkgs.util-linux
      pkgs.xvfb-run
      pkgs.xdotool
    ];
    hardware.graphics.enable = true;
    virtualisation.memorySize = 3072;
    virtualisation.cores = 2;
  };
  testScript = builtins.readFile ./portable_session_test.py + ''
    start_all()
    machine.wait_for_unit("polkit.service")
    image = "/home/approved/AppImage with spaces/Legion.AppImage"
    machine.succeed("install -d -o approved -g users '/home/approved/AppImage with spaces'")
    machine.succeed("install -o approved -g users -m755 ${image} " + shlex.quote(image))

    with subtest("direct FUSE launch renders with standard nix-ld support"):
        command = "xvfb-run -a -s '-screen 0 1280x800x24' sh -c " + shlex.quote(
            "export LIBGL_ALWAYS_SOFTWARE=1 GSETTINGS_BACKEND=memory; "
            "dbus-run-session -- " + shlex.quote(image) + " >/home/approved/gui.log 2>&1 & "
            "app=$!; trap 'kill $app 2>/dev/null || true' EXIT; "
            "xdotool search --sync --onlyvisible --class io.github.prnice.legion_linux_frontend "
            ">/home/approved/window.id; "
            "xdotool getwindowpid $(head -n1 /home/approved/window.id) >/home/approved/app.pid; wait $app"
        )
        machine.succeed(portable_as_user("approved", command) + " >/home/approved/display.log 2>&1 &")
        try:
            machine.wait_until_succeeds("test -s /home/approved/app.pid", timeout=timedelta(seconds=90))
        except Exception:
            print(machine.succeed("cat /home/approved/gui.log /home/approved/display.log"))
            raise
        pid = int(machine.succeed("cat /home/approved/app.pid").strip())
        assert machine.succeed("readlink /proc/" + str(pid) + "/ns/user") == machine.succeed("readlink /proc/1/ns/user")
        executable = machine.succeed(portable_as_user("approved", "readlink /proc/" + str(pid) + "/exe")).strip()
        assert executable.startswith("/tmp/.mount_"), executable
        helper = executable.rsplit("/", 1)[0] + "/libexec/legion-portable-control"
        maps = machine.succeed("cat /proc/" + str(pid) + "/maps")
        for library in ["libgtk-3.so.0", "libglib-2.0.so.0", "libpango-1.0.so.0"]:
            assert any("/usr/lib/legion_frontend/lib/" + library in line for line in maps.splitlines()), (library, maps)

    with subtest("the mounted static helper preserves trusted control and cleanup"):
        app = PortableSession("approved", helper, copy_launcher=False)
        assert app.cli == machine.succeed("readlink -f /run/current-system/sw/bin/legion_cli").strip()
        app.prepare("success")
        app.send("connect")
        app.send("authorize")
        app.send("enable")
        assert app.value("battery-conservation") == "enabled\n"
        app.send("disable")
        assert app.value("battery-conservation") == "disabled\n"
        assert ".so" not in machine.succeed("cat /proc/" + str(app.helper) + "/maps")
        app.close()
        assert_cleanup_succeeded()
        machine.fail("systemctl cat legion-control.service")
        machine.fail("systemctl cat legion-telemetry.service")
        machine.succeed(portable_as_user("approved", "cp " + shlex.quote(helper) + " /home/approved/helper"))
        for user in ["denied", "challenge"]:
            binary = "/home/" + user + "/helper"
            machine.succeed("install -o " + user + " -g users -m755 /home/approved/helper " + binary)
            code, output = machine.execute(portable_as_user(user, "timeout 15 " + binary + " --control") + " 2>&1")
            assert code not in [0, 124], (user, code, output)
            assert "CONTROL_READY" not in output, (user, output)
        machine.succeed("kill " + str(pid))
        machine.wait_until_succeeds("test ! -e " + shlex.quote(executable), timeout=timedelta(seconds=10))
  '';
}
