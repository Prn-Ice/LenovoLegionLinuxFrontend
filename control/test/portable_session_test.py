import re
import shlex
from datetime import timedelta
from urllib.parse import unquote

# Nix supplies `machine` in this script's globals. Standalone VM tests assign
# their local adapter after importing this test fragment.


def portable_as_user(user, command):
    return "runuser -u " + shlex.quote(user) + " -- sh -c " + shlex.quote(command)


class PortableSession:
    """Drive the VM-only app client while inspecting its synthetic backend."""

    def __init__(self, user, launcher, copy_launcher=True):
        self.user = user
        directory = machine.succeed(
            portable_as_user(user, "mktemp -d '/home/" + user + "/Portable app.XXXXXX'")
        ).strip()
        self.output = directory + "/client.out"
        self.input = directory + "/client.in"
        binary = launcher
        if copy_launcher:
            binary = directory + "/portable-bootstrap-probe"
            machine.succeed(portable_as_user(user, "cp " + shlex.quote(launcher) + " " + shlex.quote(binary) + "; chmod 700 " + shlex.quote(binary)))
        machine.succeed(portable_as_user(user, "mkfifo " + shlex.quote(self.input)))
        command = "exec legion-portable-test-client " + shlex.quote(binary) + " <>" + shlex.quote(self.input)
        machine.succeed(portable_as_user(user, command) + " >" + shlex.quote(self.output) + " 2>" + shlex.quote(self.output + ".err") + " &")
        try:
            machine.wait_until_succeeds("grep CLIENT_READY " + shlex.quote(self.output), timeout=timedelta(seconds=20))
        except Exception:
            print(machine.succeed("cat " + shlex.quote(self.output) + " " + shlex.quote(self.output + ".err") + "; journalctl -b --no-pager -n 50"))
            raise
        ready = machine.succeed("cat " + shlex.quote(self.output))
        match = re.search(r"CLIENT_READY client=(\d+) helper=(\d+) unit=(\S+) address=(\S+)", ready)
        assert match, ready
        self.client = int(match.group(1))
        self.helper = int(match.group(2))
        self.unit = match.group(3)
        self.address = match.group(4)
        selected_cli = re.search(r" cli=(\S+)", ready)
        self.cli = unquote(selected_cli.group(1)) if selected_cli else None
        self.runtime = "/run/" + self.unit.removesuffix(".service")

    def begin(self, command):
        previous = int(machine.succeed("wc -l <" + shlex.quote(self.output)).strip())
        machine.succeed(portable_as_user(self.user, "printf '%s\\n' " + shlex.quote(command) + " >" + shlex.quote(self.input)))
        return previous

    def expect(self, command, previous, error=None):
        expected = ("ERROR " + command + " " + error) if error else ("PASS " + command)
        try:
            machine.wait_until_succeeds("tail -n +" + str(previous + 1) + " " + shlex.quote(self.output) + " | grep -F -- " + shlex.quote(expected), timeout=timedelta(seconds=15))
        except Exception:
            print(machine.succeed("cat " + shlex.quote(self.output) + " " + shlex.quote(self.output + ".err") + "; journalctl -b --no-pager -n 50"))
            raise

    def send(self, command, error=None):
        self.expect(command, self.begin(command), error)

    def private(self, command):
        return "nsenter --target " + str(self.helper) + " --mount -- sh -c " + shlex.quote(command)

    def prepare(self, mode):
        machine.succeed(self.private("mkdir -p /tmp/legion-fixture; rm -f /tmp/legion-fixture/ready /tmp/legion-fixture/pids; printf '%s\\n' " + shlex.quote(mode) + " > /tmp/legion-fixture/mode"))

    def value(self, name):
        return machine.succeed(self.private("cat /tmp/legion-fixture/" + shlex.quote(name)))

    def wait_tree(self):
        machine.wait_until_succeeds(self.private("test -f /tmp/legion-fixture/ready"), timeout=timedelta(seconds=10))
        pids = [int(pid) for pid in self.value("pids").split()]
        assert len(pids) == 3, pids
        return pids

    def close(self):
        self.begin("close")
        machine.wait_until_succeeds("grep CLIENT_CLOSED " + shlex.quote(self.output), timeout=timedelta(seconds=8))
        machine.wait_until_succeeds("test ! -e " + self.runtime, timeout=timedelta(seconds=8))
