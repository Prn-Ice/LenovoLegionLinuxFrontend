{
  pkgs,
  image,
  runner,
}:
let
  fixtures = pkgs.callPackage ./fixtures.nix { };
  wrapped = pkgs.callPackage ../../packaging/nix/appimage.nix { inherit image; };
in
pkgs.testers.runNixOSTest {
  name = "legion-appimage-nixos";
  nodes.machine = {
    security.polkit.enable = true;
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.systemd1.manage-units" && subject.user == "approved")
          return polkit.Result.YES;
      });
    '';
    users.users.approved = {
      isNormalUser = true;
      uid = 1000;
    };
    environment.etc."legion-control-lifecycle-test-vm".text =
      "legion-control-disposable-lifecycle-vm\n";
    environment.systemPackages = [
      fixtures
      runner
      pkgs.util-linux
      pkgs.xvfb-run
      pkgs.xdotool
    ];
    hardware.graphics.enable = true;
    virtualisation.memorySize = 3072;
    virtualisation.cores = 2;
    virtualisation.additionalPaths = [ wrapped ];
    nix.settings.experimental-features = [
      "nix-command"
      "flakes"
    ];
  };
  testScript = builtins.readFile ./portable_session_test.py + ''
    start_all()
    machine.wait_for_unit("polkit.service")
    image = "/home/approved/AppImage with spaces/Legion.AppImage"
    machine.succeed("install -d -o approved -g users '/home/approved/AppImage with spaces'")
    machine.succeed("install -o approved -g users -m755 ${image} " + shlex.quote(image))

    with subtest("the public AppImage launcher renders without changing the host namespace"):
        command = "xvfb-run -a -s '-screen 0 1280x800x24' sh -c " + shlex.quote(
            "export LIBGL_ALWAYS_SOFTWARE=1 GSETTINGS_BACKEND=memory; "
            "dbus-run-session -- legion-appimage-run " + shlex.quote(image) + " >/home/approved/gui.log 2>&1 & "
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
        maps = machine.succeed("cat /proc/" + str(pid) + "/maps")
        for library in ["libgtk-3.so.0", "libglib-2.0.so.0", "libpango-1.0.so.0"]:
            assert any("/usr/lib/legion_frontend/lib/" + library in line for line in maps.splitlines()), (library, maps)
        machine.succeed("kill " + str(pid))

    with subtest("the unchanged static helper performs control with the host ownership view"):
        helper = "${wrapped}/app/usr/lib/legion_frontend/libexec/legion-portable-control"
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
  '';
}
