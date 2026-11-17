"""Local command boundary and persistent-file snapshots for disposable VMs."""

import hashlib
import os
import signal
import subprocess
import time
from pathlib import Path


class LocalMachine:
    """Run the shared session driver inside the disposable VM."""

    def execute(self, command, timeout=45):
        with subprocess.Popen(
            command,
            shell=True,
            executable="/bin/bash",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        ) as process:
            try:
                output, _ = process.communicate(timeout=timeout)
            except subprocess.TimeoutExpired as error:
                # Kill this command's shell and children, not only the shell.
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                try:
                    output, _ = process.communicate(timeout=5)
                except subprocess.TimeoutExpired as cleanup_error:
                    output = cleanup_error.stdout or error.stdout or b""
                if isinstance(output, bytes):
                    output = output.decode(errors="replace")
                raise AssertionError(
                    f"Command timed out after {timeout} seconds: {command}\n{output}"
                ) from error
            return process.returncode, output

    def succeed(self, command, timeout=45):
        code, output = self.execute(command, timeout=timeout)
        if code:
            raise AssertionError(f"Command failed ({code}): {command}\n{output}")
        return output

    def fail(self, command):
        code, output = self.execute(command)
        if code == 0:
            raise AssertionError(f"Command unexpectedly succeeded: {command}\n{output}")
        return output

    def wait_until_succeeds(self, command, timeout):
        deadline = time.monotonic() + timeout.total_seconds()
        while True:
            code, output = self.execute(command)
            if code == 0:
                return output
            if time.monotonic() >= deadline:
                raise AssertionError(f"Timed out: {command}\n{output}")
            time.sleep(0.1)


def persistent_files():
    roots = [
        "/etc/systemd/system",
        "/usr/lib/systemd/system",
        "/etc/polkit-1",
        "/usr/share/polkit-1/actions",
        "/etc/dbus-1/system.d",
        "/usr/share/dbus-1/system.d",
        "/etc/udev/rules.d",
    ]
    return {
        str(path): (
            path.lstat().st_mode,
            path.lstat().st_uid,
            str(path.readlink())
            if path.is_symlink()
            else hashlib.sha256(path.read_bytes()).hexdigest(),
        )
        for root in roots
        for path in Path(root).rglob("*")
        if path.is_file() or path.is_symlink()
    }
