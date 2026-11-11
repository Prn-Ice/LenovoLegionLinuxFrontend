"""Local command boundary and persistent-file snapshots for disposable VMs."""
import hashlib
from pathlib import Path
import subprocess
import time


class LocalMachine:
    """Run the shared session driver inside the disposable VM."""

    def execute(self, command):
        result = subprocess.run(command, shell=True, executable="/bin/bash", text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=45)
        return result.returncode, result.stdout

    def succeed(self, command):
        code, output = self.execute(command)
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
    roots = ["/etc/systemd/system", "/usr/lib/systemd/system", "/etc/polkit-1",
             "/usr/share/polkit-1/actions", "/etc/dbus-1/system.d",
             "/usr/share/dbus-1/system.d", "/etc/udev/rules.d"]
    return {
        str(path): (path.lstat().st_mode, path.lstat().st_uid,
                    str(path.readlink()) if path.is_symlink()
                    else hashlib.sha256(path.read_bytes()).hexdigest())
        for root in roots for path in Path(root).rglob("*")
        if path.is_file() or path.is_symlink()
    }
