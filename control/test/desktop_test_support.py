"""Exercise a packaged app's first launch against synthetic VM hardware."""

import os
import re
import shlex
import signal
import subprocess
from datetime import timedelta


def stop(process):
    if process.poll() is None:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=5)


def gui(
    machine, image, log_name, label, expected_executable=None, bundled_libraries=False
):
    # The controller needs root for a synthetic sysfs mount and helper readback.
    # The public app command itself always runs as the unprivileged fixture user.
    machine.succeed(
        "test $(id -u) = 0 && "
        "test $(stat -c %u /etc/legion-control-lifecycle-test-vm) = 0 && "
        "test \"$(cat /etc/legion-control-lifecycle-test-vm)\" = "
        "legion-control-disposable-lifecycle-vm && "
        "systemd-detect-virt --vm | grep -Ex 'kvm|qemu'"
    )
    conservation = "/sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/conservation_mode"
    machine.succeed(
        "mountpoint -q /sys/bus/platform/drivers || "
        "mount -t tmpfs tmpfs /sys/bus/platform/drivers"
    )
    machine.succeed(
        "mkdir -p /sys/bus/platform/drivers/ideapad_acpi/VPC2004:00 && "
        "echo 0 >" + conservation + " && echo success >/run/legion-gui-fixture-mode"
    )

    def as_user(command):
        return "runuser -u approved -- sh -c " + shlex.quote(command)

    # Hive uses the Documents directory, not XDG_DATA_HOME. A fresh HOME and an
    # explicit Documents mapping isolate preferences for every artifact launch.
    home = machine.succeed(as_user("mktemp -d /home/approved/legion-gui-XXXXXX")).strip()
    machine.succeed(as_user(
        "mkdir -p " + home + "/config && "
        "printf '%s\\n' 'XDG_DOCUMENTS_DIR=\"$HOME\"' >" + home + "/config/user-dirs.dirs"
    ))
    log = "/home/approved/" + log_name
    frame = "/home/approved/desktop-frame-" + label + ".png"
    launch = (
        "export HOME=" + home + " XDG_CONFIG_HOME=" + home + "/config "
        "XDG_DATA_HOME=" + home + "/data GSETTINGS_BACKEND=memory "
        "GDK_BACKEND=x11 LIBGL_ALWAYS_SOFTWARE=1; "
        "unset JAVA_HOME LD_LIBRARY_PATH; "
        "printf '%s' \"$DISPLAY\" >" + home + "/display; "
        "printf '%s' \"$XAUTHORITY\" >" + home + "/authority; "
        + shlex.quote(image) + " >" + shlex.quote(log) + " 2>&1 & "
        "app=$!; trap 'kill $app 2>/dev/null || true' EXIT; "
        "xdotool search --sync --onlyvisible --class "
        "io.github.prnice.legion_linux_frontend >" + home + "/window; "
        "xdotool windowsize $(head -n1 " + home + "/window) 1280 720; "
        "xdotool getwindowpid $(head -n1 " + home + "/window) >" + home + "/pid; "
        "wait $app; status=$?; printf '%s' \"$status\" >" + home + "/exit; exit $status"
    )
    command = "xvfb-run -a -s '-screen 0 1280x900x24' dbus-run-session -- sh -c " + shlex.quote(launch)
    machine.succeed(as_user(
        "setsid " + command + " >" + home + "/display.log 2>&1 & "
        "echo $! >" + home + "/runner"
    ))

    def desktop(command):
        return as_user(
            "DISPLAY=$(cat " + home + "/display) "
            "XAUTHORITY=$(cat " + home + "/authority) " + command
        )

    def click(x, y):
        return desktop(
            "xdotool mousemove --window $(head -n1 " + home + "/window) "
            + str(x) + " " + str(y) + " click 1"
        )

    def wait_text(text, region, layout=7):
        command = desktop("sh -c " + shlex.quote(
            "import -window root " + shlex.quote(frame) + " && "
            "convert " + shlex.quote(frame) + " -crop " + region + " -resize 300% "
            + home + "/label.png && tesseract " + home + "/label.png stdout --psm "
            + str(layout) + " 2>/dev/null"
        ))
        machine.wait_until_succeeds(
            command + " | grep -Fi -- " + shlex.quote(text), timeout=timedelta(seconds=30)
        )

    unit_query = "systemctl list-units --type=service --state=active --plain --no-legend 'legion-portable-control-*' | awk '{print $1}'"
    try:
        machine.wait_until_succeeds("test -s " + home + "/pid", timeout=timedelta(seconds=120))
        wait_text("Dashboard", "380x32+288+7")
        machine.wait_until_succeeds("test -f " + home + "/preferences.hive", timeout=timedelta(seconds=10))
        pid = int(machine.succeed("cat " + home + "/pid").strip())
        executable = machine.succeed("readlink -f /proc/" + str(pid) + "/exe").strip()
        if expected_executable is not None:
            assert executable == expected_executable, executable
        machine.succeed("test -x " + shlex.quote(executable.rsplit("/", 1)[0] + "/libexec/legion-portable-control"))
        if bundled_libraries:
            maps = machine.succeed("cat /proc/" + str(pid) + "/maps")
            for library in ("libgtk-3.so.0", "libglib-2.0.so.0", "libpango-1.0.so.0"):
                assert any(
                    "/usr/lib/legion_frontend/lib/" + library in line
                    for line in maps.splitlines()
                ), (library, maps)
            machine.succeed("cp /proc/" + str(pid) + "/maps " + shlex.quote("/home/approved/appimage-runtime-" + label + ".txt"))
        assert machine.succeed(unit_query).strip() == "", "Read-only startup launched a helper"

        # Use the existing Hardware page control without visiting Settings or
        # restarting. The CLI writes only its private synthetic fixture files.
        machine.succeed(click(90, 228))
        machine.succeed(desktop(
            "xdotool mousemove --window $(head -n1 " + home + "/window) "
            "1100 600 click --repeat 18 --delay 50 5"
        ))
        wait_text("mode", "260x25+359+648")
        machine.succeed(click(734, 667))
        machine.wait_until_succeeds("test -n \"$(" + unit_query + ")\"", timeout=timedelta(seconds=30))
        unit = machine.succeed(unit_query).strip()
        assert re.fullmatch(r"legion-portable-control-[0-9a-f-]+\.service", unit), unit
        helper_pid = int(machine.succeed("systemctl show --property=MainPID --value " + unit).strip())
        readback = "nsenter --target " + str(helper_pid) + " --mount -- cat /tmp/legion-fixture/battery-conservation"
        machine.wait_until_succeeds(readback + " | grep -x enabled", timeout=timedelta(seconds=15))
        machine.succeed("echo 1 >" + conservation)
        machine.wait_until_succeeds(
            click(1142, 23) + "; " + click(734, 667) + "; " + readback + " | grep -x disabled",
            timeout=timedelta(seconds=20),
        )
        machine.succeed("echo 0 >" + conservation)
        print("PASS: first-launch helper write/readback/restore from " + label, flush=True)

        # Inspect Settings only after proving first-launch control. There is no
        # authorization chooser to select and no next-launch choice to save.
        machine.succeed(click(90, 427))
        wait_text("Hardware control", "1280x720+0+0", 11)
        settings = machine.succeed(desktop(
            "tesseract " + home + "/label.png stdout --psm 11 2>/dev/null"
        ))
        settings = " ".join(settings.lower().split())
        for obsolete in ("installed service", "use on next launch", "in use now:"):
            assert obsolete not in settings, settings

        # Xvfb may close its socket while xdotool finishes; the app's status wins.
        machine.execute(click(1258, 23))
        machine.wait_until_succeeds("test -s " + home + "/exit", timeout=timedelta(seconds=15))
        assert machine.succeed("cat " + home + "/exit").strip() == "0", machine.succeed("cat " + shlex.quote(log))
        machine.wait_until_succeeds("test ! -e /proc/" + str(pid), timeout=timedelta(seconds=10))
        machine.wait_until_succeeds("test ! -e /proc/" + str(helper_pid), timeout=timedelta(seconds=10))
        runtime = "/run/" + unit.removesuffix(".service")
        machine.wait_until_succeeds("test ! -e " + runtime, timeout=timedelta(seconds=10))
        cleanup = unit.removesuffix(".service") + "-cleanup.service"
        machine.wait_until_succeeds(
            "journalctl -b --no-pager -u " + cleanup + " | grep -F 'Legion control cleanup complete.'",
            timeout=timedelta(seconds=10),
        )
        machine.wait_until_succeeds("test -z \"$(" + unit_query + ")\"", timeout=timedelta(seconds=10))
        gui_log = machine.succeed("cat " + shlex.quote(log))
        for diagnostic in ("Pango-CRITICAL", "GLib-CRITICAL", "GLib-GObject-CRITICAL"):
            assert diagnostic not in gui_log, gui_log
        print("PASS: close button exits normally and cleans up the helper from " + label, flush=True)
    except Exception:
        print(machine.execute("cat " + shlex.quote(log) + " " + home + "/display.log; journalctl -b --no-pager -u 'legion-portable-control-*'")[1])
        raise
    finally:
        machine.execute(as_user("kill -TERM -$(cat " + home + "/runner) 2>/dev/null || true"))
