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
      pkgs.imagemagick
      (pkgs.tesseract.override { enableLanguages = [ "eng" ]; })
    ];
    hardware.graphics.enable = true;
    virtualisation.memorySize = 2048;
    virtualisation.cores = 2;
  };
  testScript = builtins.readFile ./portable_session_test.py + ''
    import importlib.util

    desktop_spec = importlib.util.spec_from_file_location("desktop_test_support", "${./desktop_test_support.py}")
    assert desktop_spec is not None and desktop_spec.loader is not None
    desktop = importlib.util.module_from_spec(desktop_spec)
    desktop_spec.loader.exec_module(desktop)

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

    with subtest("the public launcher uses the helper on first launch and closes normally"):
        desktop.gui(machine, "legion_frontend", "gui.log", "Nix frontend", expected_executable="${bundle}/legion_frontend")

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
        assert_cleanup_succeeded()
  '';
}
