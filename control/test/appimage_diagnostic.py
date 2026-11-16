"""Observe a normal WM close of the exact app and retain its loaded libraries."""

import hashlib
import json
import os
import pwd
import shutil
import stat
import subprocess
import sys
import time
from pathlib import Path

from Xlib import display


HOME = Path.home()
ROOT = HOME / "appimage-diagnostic"


def wait_for(check, seconds, message):
    deadline = time.monotonic() + seconds
    while not check():
        assert time.monotonic() < deadline, message
        time.sleep(0.05)


def window_ids(window):
    connection = display.Display()
    def descendants(resource):
        return [resource.id] + [child_id for child in resource.query_tree().children
                                for child_id in descendants(child)]
    try:
        return descendants(connection.create_resource_object("window", int(window)))
    finally:
        connection.close()


def close_events(directory, windows, since):
    path = directory / "events.jsonl"
    if not path.exists():
        return []
    events = [json.loads(line) for line in path.read_text().splitlines()]
    return [event for event in events if event["window"] in windows
            and event["monotonic"] >= since
            and event["event"] == "WM_DELETE_WINDOW"]


def before_close(pid, window, label):
    directory = ROOT / label
    process = Path(f"/proc/{pid}")
    executable = str((process / "exe").resolve())
    metadata = {
        "pid": int(pid), "window": int(window), "executable": executable,
        "windows": window_ids(window), "files": {},
    }
    (directory / "process.json").write_text(json.dumps(metadata, indent=2) + "\n")
    maps = (process / "maps").read_text()
    (directory / "maps.txt").write_text(maps)
    (directory / "process-environment.bin").write_bytes((process / "environ").read_bytes())
    files = {line.split(maxsplit=5)[5] for line in maps.splitlines()
             if len(line.split(maxsplit=5)) == 6 and line.split(maxsplit=5)[5].startswith("/")}
    files.add(executable)
    identities = {}
    for name in [executable] + sorted(files - {executable}):
        source = Path(name)
        if not source.is_file():
            continue
        target = directory / "rootfs" / name.lstrip("/")
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        identities[name] = hashlib.sha256(target.read_bytes()).hexdigest()
    metadata["files"] = identities
    protocols = subprocess.check_output(["xprop", "-id", window, "WM_PROTOCOLS"], text=True, timeout=10)
    assert "WM_DELETE_WINDOW" in protocols, protocols
    (directory / "protocols.txt").write_text(protocols)
    (directory / "process.json").write_text(json.dumps(metadata, indent=2) + "\n")
    subprocess.run(["xwininfo", "-id", window, "-all"], check=False, timeout=10,
                   stdout=(directory / "window.txt").open("w"), stderr=subprocess.STDOUT)
    subprocess.run(["import", "-window", "root", str(directory / "before-close.png")],
                   check=True, timeout=10)
    metadata["requested_at"] = time.monotonic()
    (directory / "request.json").write_text(json.dumps(metadata, indent=2) + "\n")


def after_close(label, status):
    directory = ROOT / label
    (directory / "exit.json").write_text(json.dumps({
        "status": status, "observed_at": time.monotonic(),
    }) + "\n")
    request = json.loads((directory / "request.json").read_text())
    error = None
    try:
        wait_for(lambda: close_events(directory, [request["window"]], request["requested_at"]),
                 5, "WM_DELETE_WINDOW was not independently observed")
    except AssertionError as failure:
        error = str(failure)
    evidence = {"events": close_events(directory, [request["window"]], request["requested_at"]),
                "error": error, "application_status": status}
    (directory / "delivery.json").write_text(json.dumps(evidence, indent=2) + "\n")
    print("CLOSE_DELIVERY " + json.dumps(evidence), flush=True)
    if status == 0:
        assert error is None, error


def preflight(directory):
    (HOME / "gtk-delete-received").unlink(missing_ok=True)
    appdir = "/opt/appimage-gtk-fixture/squashfs-root"
    environment = os.environ | {
        "LD_LIBRARY_PATH": appdir + "/usr/lib/legion_frontend/lib",
        "GSETTINGS_SCHEMA_DIR": appdir + "/usr/share/glib-2.0/schemas",
        "GIO_MODULE_DIR": appdir + "/usr/lib/legion_frontend/lib/gio/modules",
        "FONTCONFIG_FILE": appdir + "/usr/etc/fonts/fonts.conf",
        "XDG_DATA_DIRS": appdir + "/usr/share:/usr/local/share:/usr/share",
    }
    with (directory / "gtk-preflight.log").open("w") as log:
        process = subprocess.Popen([sys.executable, "/opt/legion-vm-tests/appimage_gtk_fixture.py"],
                                   env=environment, stdout=log, stderr=log)
        windows = []
        def ready():
            result = subprocess.run(["xdotool", "search", "--onlyvisible", "--pid", str(process.pid)],
                                    text=True, capture_output=True, timeout=5, check=False)
            windows[:] = result.stdout.splitlines() if result.returncode == 0 else []
            return windows
        wait_for(ready, 15, "GTK preflight window did not appear")
        window = windows[0]
        targets = window_ids(window)
        since = time.monotonic()
        subprocess.run(["wmctrl", "-ic", hex(int(window))],
                       check=True, timeout=5)
        assert process.wait(timeout=10) == 0
        wait_for(lambda: close_events(directory, targets, since), 5,
                 "GTK WM_DELETE_WINDOW delivery was not recorded")
        assert (HOME / "gtk-delete-received").read_text() == "delete-event\n"
        (directory / "gtk-delivery.json").write_text(json.dumps(
            close_events(directory, targets, since), indent=2) + "\n")
        assert "-CRITICAL" not in (directory / "gtk-preflight.log").read_text()
        print("PASS: GTK delete-event and X RECORD independently confirm normal WM close delivery", flush=True)


def main():
    image, label = sys.argv[1:]
    directory = ROOT / label
    directory.mkdir(parents=True)
    uid = os.getuid()
    runtime = Path(os.environ["XDG_RUNTIME_DIR"]).stat()
    assert uid != 0 and runtime.st_uid == uid and stat.S_IMODE(runtime.st_mode) == 0o700
    assert str(HOME) == pwd.getpwuid(uid).pw_dir == os.environ["HOME"]
    assert os.environ["DBUS_SESSION_BUS_ADDRESS"]
    (directory / "environment.json").write_text(json.dumps(dict(os.environ), indent=2) + "\n")
    with (directory / "renderer.txt").open("w") as log:
        subprocess.run(["glxinfo", "-B"], check=True, timeout=15, stdout=log, stderr=log)
    with (directory / "observer.log").open("w") as log, (directory / "openbox.log").open("w") as wm_log:
        observer = subprocess.Popen([sys.executable, "/opt/legion-vm-tests/appimage_close_observer.py", str(directory)],
                                    stdout=log, stderr=log)
        wm = subprocess.Popen(["openbox"], stdout=wm_log, stderr=wm_log)
        try:
            wait_for(lambda: (directory / "observer-ready").exists(), 10, "X RECORD observer did not start")
            wait_for(lambda: "_NET_SUPPORTING_WM_CHECK(WINDOW)" in subprocess.check_output(
                ["xprop", "-root", "_NET_SUPPORTING_WM_CHECK"], text=True, timeout=5),
                15, "Openbox did not register")
            preflight(directory)
            if label == "preflight":
                return
            from desktop_test_support import gui
            gui(image, f"appimage-gui-{label}.log", label, bundled_libraries=True)
        finally:
            # Only diagnostic helpers are signalled, never the app under test.
            for helper in [observer, wm]:
                if helper.poll() is None:
                    helper.terminate()
                    helper.wait(timeout=5)


if __name__ == "__main__":
    main()
