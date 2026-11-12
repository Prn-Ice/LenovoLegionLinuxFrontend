{ pkgs, image }:
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
    programs.appimage.enable = true;
    environment.etc."legion-control-lifecycle-test-vm".text =
      "legion-control-disposable-lifecycle-vm\n";
    environment.systemPackages = [
      fixtures
      pkgs.util-linux
      pkgs.xvfb-run
      pkgs.xdotool
      pkgs.xorg.xprop
      pkgs.sway
      pkgs.grim
      pkgs.jq
      pkgs.imagemagick
      (pkgs.tesseract.override { enableLanguages = [ "eng" ]; })
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

    with subtest("fixed-location read discovery works inside the official runner"):
        output = machine.succeed(portable_as_user("approved", "APPIMAGE_DEBUG_EXEC=${fixtures}/bin/host-cli-read-test appimage-run " + shlex.quote(image)))
        expected_cli = machine.succeed("readlink -f /run/current-system/sw/bin/legion_cli").strip()
        assert "READ_CLI " + expected_cli in output, output
        assert re.search(r"(?m)^ok \d+ /trusted-executable/read-cli$", output), output

    # Kernel files below this mount are synthetic and exist only in this VM.
    conservation = "/sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/conservation_mode"
    machine.succeed("mount -t tmpfs tmpfs /sys/bus/platform/drivers")
    machine.succeed("mkdir -p /sys/bus/platform/drivers/ideapad_acpi/VPC2004:00")
    machine.succeed("echo 0 >" + conservation)
    machine.succeed("echo success >/run/legion-gui-fixture-mode")

    def start_gui():
        machine.succeed("rm -f /home/approved/app.pid /home/approved/window.id /home/approved/app.exit")
        command = "xvfb-run -a -s '-screen 0 1280x900x24' dbus-run-session -- sh -c " + shlex.quote(
            "export LIBGL_ALWAYS_SOFTWARE=1 GSETTINGS_BACKEND=memory; "
            "printf '%s' \"$DISPLAY\" >/home/approved/display; "
            "appimage-run " + shlex.quote(image) + " >>/home/approved/gui.log 2>&1 & "
            "app=$!; trap 'kill $app 2>/dev/null || true' EXIT; "
            "xdotool search --sync --onlyvisible --class io.github.prnice.legion_linux_frontend >/home/approved/window.id; "
            "xdotool windowsize $(head -n1 /home/approved/window.id) 1280 720; "
            "xdotool getwindowpid $(head -n1 /home/approved/window.id) >/home/approved/app.pid; "
            "wait $app; status=$?; printf '%s' \"$status\" >/home/approved/app.exit; exit \"$status\""
        )
        machine.succeed(portable_as_user("approved", command) + " >>/home/approved/display.log 2>&1 &")
        try:
            machine.wait_until_succeeds("test -s /home/approved/app.pid", timeout=timedelta(seconds=90))
        except Exception:
            print(machine.succeed("cat /home/approved/gui.log /home/approved/display.log"))
            raise
        return int(machine.succeed("cat /home/approved/app.pid").strip())

    def desktop(command):
        return portable_as_user("approved", "DISPLAY=$(cat /home/approved/display) " + command)

    def click(x, y):
        return desktop("xdotool mousemove --window $(head -n1 /home/approved/window.id) " + str(x) + " " + str(y) + " click 1")

    def screenshot(name):
        machine.succeed(desktop("magick import -window root /home/approved/" + name + ".png"))
        machine.copy_from_machine("/home/approved/" + name + ".png")

    def close_gui():
        # Xvfb exits with the app, so xdotool may lose its connection while
        # finishing the click. The app's recorded exit status is authoritative.
        machine.execute(click(1258, 23))
        machine.wait_until_succeeds("test -s /home/approved/app.exit", timeout=timedelta(seconds=15))
        assert machine.succeed("cat /home/approved/app.exit").strip() == "0", machine.succeed("cat /home/approved/gui.log")

    def wait_text(text, region):
        command = desktop("sh -c " + shlex.quote("magick import -window root /home/approved/current.png && magick /home/approved/current.png -crop " + region + " -resize 300% /home/approved/label.png && tesseract /home/approved/label.png stdout --psm 7 2>/dev/null"))
        try:
            machine.wait_until_succeeds(command + " | grep -Fi -- " + shlex.quote(text), timeout=timedelta(seconds=30))
        except Exception:
            print(machine.succeed(command))
            screenshot("missing-ui-label")
            raise

    with subtest("the actual app saves temporary mode through Settings"):
        pid = start_gui()
        wait_text("Dashboard", "380x32+288+7")
        # The fixed viewport makes these UI actions reproducible. Wait for the
        # visible labels, then verify the saved mode and backend readback.
        machine.succeed(click(90, 427))
        wait_text("Temporary helper", "145x24+977+294")
        machine.succeed(click(1040, 305))
        wait_text("Use a temporary helper", "300x32+500+232")
        machine.succeed(click(770, 455))
        machine.wait_until_succeeds("grep -aq temporaryHelper /home/approved/preferences.hive", timeout=timedelta(seconds=10))
        icon = machine.succeed(desktop("xprop -id $(head -n1 /home/approved/window.id) _NET_WM_ICON"))
        assert "not found" not in icon and "no such atom" not in icon, icon
        close_gui()
        machine.wait_until_succeeds("test ! -e /proc/" + str(pid), timeout=timedelta(seconds=10))

    with subtest("official appimage-run opens the temporary-control app"):
        pid = start_gui()
        assert machine.succeed("readlink /proc/" + str(pid) + "/ns/user") != machine.succeed("readlink /proc/1/ns/user")
        executable = machine.succeed("readlink /proc/" + str(pid) + "/exe").strip()
        assert "/.cache/appimage-run/" in executable, executable
        helper = executable.rsplit("/", 1)[0] + "/libexec/legion-portable-control"
        maps = machine.succeed("cat /proc/" + str(pid) + "/maps")
        for library in ["libgtk-3.so.0", "libglib-2.0.so.0", "libpango-1.0.so.0"]:
            assert any("/usr/lib/legion_frontend/lib/" + library in line for line in maps.splitlines()), (library, maps)

    with subtest("the GUI changes and restores a synthetic hardware setting"):
        machine.succeed(click(90, 228))
        scroll = desktop("xdotool mousemove --window $(head -n1 /home/approved/window.id) 1100 600 click --repeat 18 --delay 50 5")
        machine.succeed(scroll)
        wait_text("mode", "260x25+359+648")
        unit_query = "systemctl list-units --type=service --state=active --plain --no-legend 'legion-portable-control-*' | awk '{print $1}'"
        try:
            machine.succeed(click(734, 667))
            machine.wait_until_succeeds("test -n \"$(" + unit_query + ")\"", timeout=timedelta(seconds=30))
            unit = machine.succeed(unit_query).strip()
            assert re.fullmatch(r"legion-portable-control-[0-9a-f-]+\.service", unit), unit
            helper_pid = int(machine.succeed("systemctl show --property=MainPID --value " + unit).strip())
            readback = "nsenter --target " + str(helper_pid) + " --mount -- cat /tmp/legion-fixture/battery-conservation"
            machine.wait_until_succeeds(readback + " | grep -x enabled", timeout=timedelta(seconds=15))
            assert ".so" not in machine.succeed("cat /proc/" + str(helper_pid) + "/maps")
            machine.succeed("echo 1 >" + conservation)
            machine.wait_until_succeeds(click(1142, 23) + "; " + click(734, 667) + "; " + readback + " | grep -x disabled", timeout=timedelta(seconds=20))
            screenshot("temporary-control-restored")
        except Exception:
            screenshot("temporary-control-failure")
            print(machine.execute("cat /home/approved/gui.log; journalctl -b --no-pager -u 'legion-portable-control-*'")[1])
            raise
        close_gui()
        machine.wait_until_succeeds("test ! -e /proc/" + str(helper_pid), timeout=timedelta(seconds=10))
        cleanup = unit.removesuffix(".service") + "-cleanup.service"
        machine.wait_until_succeeds("journalctl -b --no-pager -u " + cleanup + " | grep -F 'Legion control cleanup complete.'", timeout=timedelta(seconds=10))
        assert_cleanup_succeeded()
        machine.fail("systemctl cat legion-control.service")
        machine.fail("systemctl cat legion-telemetry.service")

    machine.copy_from_machine("/home/approved/gui.log")

    with subtest("official appimage-run closes normally on Wayland"):
        machine.succeed("install -d -o approved -g users -m700 /run/user/1000")
        machine.succeed("printf '%s\\n' 'output HEADLESS-1 resolution 1280x900' 'default_border none' >/home/approved/sway.conf")

        def wayland(command):
            environment = "env XDG_RUNTIME_DIR=/run/user/1000 SWAYSOCK=/run/user/1000/sway.sock WAYLAND_DISPLAY=wayland-1 GDK_BACKEND=wayland LIBGL_ALWAYS_SOFTWARE=1 GSETTINGS_BACKEND=memory "
            return portable_as_user("approved", environment + "sh -c " + shlex.quote(command))

        compositor = "WLR_BACKENDS=headless WLR_RENDERER=pixman dbus-run-session -- sway -c /home/approved/sway.conf"
        machine.succeed(wayland(compositor) + " >/home/approved/sway.log 2>&1 &")
        try:
            machine.wait_until_succeeds("test -S /run/user/1000/sway.sock", timeout=timedelta(seconds=45))
            for attempt in range(10):
                machine.succeed("rm -f /home/approved/wayland.exit")
                launch = "appimage-run " + shlex.quote(image) + " >>/home/approved/wayland.log 2>&1; printf '%s' \"$?\" >/home/approved/wayland.exit"
                machine.succeed(wayland("dbus-run-session -- sh -c " + shlex.quote(launch)) + " >/home/approved/wayland-launcher.log 2>&1 &")
                visible = "swaymsg -t get_tree | jq -e '.. | objects | select(.app_id? == \"io.github.prnice.legion_linux_frontend\")'"
                machine.wait_until_succeeds(wayland(visible), timeout=timedelta(seconds=60))
                frame = "grim /home/approved/wayland.png && magick /home/approved/wayland.png -crop 380x32+288+7 -resize 300% /home/approved/wayland-label.png && tesseract /home/approved/wayland-label.png stdout --psm 7 2>/dev/null | grep -Fi Dashboard"
                machine.wait_until_succeeds(wayland(frame), timeout=timedelta(seconds=30))
                # Sway's kill command sends the native window-close request;
                # it does not send a process signal.
                machine.succeed(wayland("swaymsg '[app_id=\"io.github.prnice.legion_linux_frontend\"] kill'"))
                machine.wait_until_succeeds("test -s /home/approved/wayland.exit", timeout=timedelta(seconds=15))
                assert machine.succeed("cat /home/approved/wayland.exit").strip() == "0", machine.succeed("cat /home/approved/wayland.log")
        except Exception:
            print(machine.execute("cat /home/approved/wayland.log /home/approved/sway.log")[1])
            raise
        finally:
            machine.copy_from_machine("/home/approved/wayland.log")
            machine.execute(wayland("swaymsg exit"))

    with subtest("the same helper still rejects denied approval and a missing agent"):
        for user in ["denied", "challenge"]:
            binary = "/home/" + user + "/helper"
            machine.succeed("install -o " + user + " -g users -m755 " + shlex.quote(helper) + " " + binary)
            code, output = machine.execute(portable_as_user(user, "timeout 15 " + binary + " --control") + " 2>&1")
            assert code not in [0, 124], (user, code, output)
            assert "CONTROL_READY" not in output, (user, output)
  '';
}
