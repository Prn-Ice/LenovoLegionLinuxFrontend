"""Launch a packaged desktop and wait for its first visible Flutter frame."""

import os
import signal
import subprocess
import tempfile
import time
from pathlib import Path


def stop(process):
    if process.poll() is None:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=5)


def gui(image, log_name, label, expected_executable=None):
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
            deadline = time.monotonic() + 30
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
                    pid = subprocess.check_output(
                        ["xdotool", "getwindowpid", result.stdout.splitlines()[0]],
                        text=True,
                    ).strip()
                    executable = Path("/proc/" + pid + "/exe").resolve()
                    if expected_executable is not None:
                        assert executable == Path(expected_executable), executable
                    print("PASS: visible Flutter window from " + label, flush=True)
                    break
                if process.poll() is not None or time.monotonic() >= deadline:
                    raise AssertionError(
                        "Desktop window did not appear:\n" + log_path.read_text()
                    )
                time.sleep(0.1)
        finally:
            stop(process)
