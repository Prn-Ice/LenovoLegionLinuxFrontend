"""Launch the packaged app, wait for Dashboard, and check a normal close."""

import os
import signal
import subprocess
import tempfile
import time
from pathlib import Path

from appimage_diagnostic import before_close, after_close


def stop(process):
    if process.poll() is None:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=5)


def gui(image, log_name, label, expected_executable=None, bundled_libraries=False):
    assert os.getuid() != 0
    log_path = Path.home() / log_name
    with (
        tempfile.TemporaryDirectory(prefix="legion-gui-", dir=Path.home()) as temporary,
        log_path.open("w") as log,
    ):
        environment = dict(
            os.environ,
            GSETTINGS_BACKEND="memory",
            GDK_BACKEND="x11",
            LIBGL_ALWAYS_SOFTWARE="1",
            XDG_CONFIG_HOME=temporary + "/config",
            XDG_DATA_HOME=temporary + "/data",
        )
        environment.pop("JAVA_HOME", None)
        environment.pop("LD_LIBRARY_PATH", None)
        process = subprocess.Popen(
            [image], stdout=log, stderr=log, env=environment, start_new_session=True
        )
        try:
            started = time.monotonic()
            deadline = started + 120
            while True:
                result = subprocess.run(
                    [
                        "xdotool",
                        "search",
                        "--onlyvisible",
                        "--class",
                        "io.github.prnice.legion_linux_frontend",
                    ],
                    text=True,
                    capture_output=True,
                    check=False,
                )
                if result.returncode == 0 and process.poll() is None:
                    window = result.stdout.splitlines()[0]
                    frame = Path.home() / ("desktop-frame-" + label + ".png")
                    subprocess.run(
                        ["import", "-window", window, str(frame)],
                        check=True,
                        capture_output=True,
                    )
                    cropped = temporary + "/dashboard.png"
                    subprocess.run(
                        [
                            "convert",
                            str(frame),
                            "-crop",
                            "380x32+288+7",
                            "-resize",
                            "300%",
                            cropped,
                        ],
                        check=True,
                        capture_output=True,
                    )
                    text = subprocess.check_output(
                        ["tesseract", cropped, "stdout", "--psm", "7"],
                        text=True,
                        stderr=subprocess.DEVNULL,
                    )
                    if "dashboard" not in text.lower():
                        if time.monotonic() >= deadline:
                            raise AssertionError(
                                "Dashboard did not render:\n" + log_path.read_text()
                            )
                        time.sleep(0.1)
                        continue
                    pid = subprocess.check_output(
                        ["xdotool", "getwindowpid", result.stdout.splitlines()[0]],
                        text=True,
                    ).strip()
                    executable = Path("/proc/" + pid + "/exe").resolve()
                    if expected_executable is not None:
                        assert executable == Path(expected_executable), executable
                    if bundled_libraries:
                        maps = Path("/proc/" + pid + "/maps").read_text()
                        for library in (
                            "libgtk-3.so.0",
                            "libglib-2.0.so.0",
                            "libpango-1.0.so.0",
                        ):
                            assert any(
                                "/usr/lib/legion_frontend/lib/" + library in line
                                for line in maps.splitlines()
                            ), (library, maps)
                        (
                            Path.home() / ("appimage-runtime-" + label + ".txt")
                        ).write_text(maps)
                    print(
                        f"PASS: visible Flutter window from {label} after "
                        f"{time.monotonic() - started:.1f}s",
                        flush=True,
                    )
                    before_close(pid, window, label)
                    subprocess.run(["wmctrl", "-ic", hex(int(window))], check=True, timeout=10)
                    status = process.wait(timeout=15)
                    after_close(label, status)
                    assert status == 0, (status, log_path.read_text())
                    for diagnostic in (
                        "Pango-CRITICAL",
                        "GLib-CRITICAL",
                        "GLib-GObject-CRITICAL",
                    ):
                        assert diagnostic not in log_path.read_text(), (
                            log_path.read_text()
                        )
                    print("PASS: close button exits normally from " + label, flush=True)
                    break
                if process.poll() is not None or time.monotonic() >= deadline:
                    raise AssertionError(
                        "Desktop window did not appear "
                        f"(exit status: {process.poll()}):\n" + log_path.read_text()
                    )
                time.sleep(0.1)
        finally:
            # A live failure is left for VM teardown, not closed by a diagnostic signal.
            if process.poll() is not None:
                stop(process)
