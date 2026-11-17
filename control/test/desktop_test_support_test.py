"""Check the desktop driver's safety and failure gates without launching an app."""

import contextlib
import io
import shlex
import subprocess
import unittest

from desktop_test_support import gui


class FixtureMachine:
    def __init__(self, *, allowed=True, exit_status="0", log="", settings="Hardware control", cleanup=True, diagnostic_failure=False):
        self.allowed = allowed
        self.exit_status = exit_status
        self.log = log
        self.settings = settings
        self.cleanup = cleanup
        self.diagnostic_failure = diagnostic_failure
        self.commands = []
        self.unit_reads = 0
        self.home = "/home/approved/legion-gui-fixture"

    def succeed(self, command):
        self.commands.append(command)
        if "systemd-detect-virt --vm" in command and not self.allowed:
            raise AssertionError("Not a disposable VM")
        if "mktemp -d" in command:
            return self.home + "\n"
        if command == "cat " + self.home + "/pid":
            return "101\n"
        if "readlink -f /proc/" in command:
            return "/app/legion_frontend\n"
        if command.startswith("systemctl list-units"):
            self.unit_reads += 1
            return "" if self.unit_reads == 1 else "legion-portable-control-abcd.service\n"
        if command.startswith("systemctl show --property=MainPID"):
            return "202\n"
        if command == "cat " + self.home + "/exit":
            return self.exit_status
        if command == "cat /home/approved/gui.log":
            return self.log
        if "tesseract" in command and "import -window" not in command:
            return self.settings
        return ""

    def wait_until_succeeds(self, command, *, timeout):
        self.commands.append(command)
        if "Legion control cleanup complete." in command and not self.cleanup:
            raise AssertionError("Helper cleanup did not finish")

    def execute(self, command):
        self.commands.append(command)
        if self.diagnostic_failure and "desktop-diagnostics-" in command:
            raise AssertionError("Diagnostic fixture timed out")
        return 0, ""


class DesktopDriverTest(unittest.TestCase):
    def run_gui(self, machine):
        with contextlib.redirect_stdout(io.StringIO()):
            gui(machine, "legion_frontend", "gui.log", "fixture")

    def test_refuses_fixture_writes_outside_the_disposable_vm(self):
        machine = FixtureMachine(allowed=False)
        with self.assertRaisesRegex(AssertionError, "Not a disposable VM"):
            self.run_gui(machine)
        self.assertEqual(len(machine.commands), 1)
        self.assertNotIn("mount -t", machine.commands[0])

    def test_first_launch_writes_before_inspecting_settings_and_closes_once(self):
        machine = FixtureMachine()
        self.run_gui(machine)
        commands = machine.commands
        launches = [command for command in commands if "setsid env XDG_RUNTIME_DIR=" in command]
        self.assertEqual(len(launches), 1)
        self.assertIn("export HOME=" + machine.home, launches[0])
        self.assertIn("runuser -u approved", launches[0])
        self.assertIn("XDG_RUNTIME_DIR=" + machine.home + "/runtime", launches[0])
        self.assertIn("test -f " + machine.home + "/preferences.hive", commands)
        executable = next(command for command in commands if "readlink -f /proc/" in command)
        self.assertIn("runuser -u approved", executable)
        ready = next(i for i, command in enumerate(commands) if "Collect history" in command)
        scroll = next(i for i, command in enumerate(commands) if "--repeat 18" in command)
        self.assertLess(ready, scroll)
        restored = next(i for i, command in enumerate(commands) if "grep -x disabled" in command)
        settings = next(i for i, command in enumerate(commands) if "427 click 1" in command)
        self.assertLess(restored, settings)
        self.assertEqual(sum("1258 23 click 1" in command for command in commands), 1)
        self.assertTrue(any("Legion control cleanup complete." in command for command in commands))
        self.assertIn("kill -TERM", commands[-1])

    def test_nonzero_window_close_remains_a_failure(self):
        with self.assertRaises(AssertionError):
            self.run_gui(FixtureMachine(exit_status="139"))

    def test_diagnostic_failure_does_not_replace_the_original_close_failure(self):
        with self.assertLogs(level="ERROR"), self.assertRaisesRegex(AssertionError, "Original close failure"):
            self.run_gui(FixtureMachine(
                exit_status="139", log="Original close failure", diagnostic_failure=True
            ))

    def test_ocr_is_bounded_and_does_not_enlarge_full_window_frames(self):
        machine = FixtureMachine()
        self.run_gui(machine)
        recognition = [command for command in machine.commands if "tesseract" in command]
        self.assertTrue(recognition)
        for command in recognition:
            self.assertIn("timeout 15 env OMP_THREAD_LIMIT=1 tesseract", command)
        for command in recognition:
            if "-crop 1280x720+0+0" in command:
                self.assertIn("-resize 100%", command)
            elif "-crop 380x32+288+7" in command:
                self.assertIn("-resize 300%", command)

    def test_generated_commands_and_nested_scripts_have_valid_shell_syntax(self):
        machine = FixtureMachine()
        self.run_gui(machine)
        pending = list(machine.commands)
        checked = set()
        while pending:
            command = pending.pop()
            if command in checked:
                continue
            checked.add(command)
            subprocess.run(["sh", "-n", "-c", command], check=True, timeout=5)
            words = shlex.split(command)
            for index, word in enumerate(words[:-2]):
                if word == "sh" and words[index + 1] == "-c":
                    pending.append(words[index + 2])

    def test_runtime_criticals_remain_failures(self):
        for diagnostic in ("Pango-CRITICAL", "GLib-CRITICAL", "GLib-GObject-CRITICAL"):
            with self.subTest(diagnostic=diagnostic), self.assertRaisesRegex(AssertionError, diagnostic):
                self.run_gui(FixtureMachine(log=diagnostic))

    def test_missing_helper_cleanup_remains_a_failure(self):
        with self.assertRaisesRegex(AssertionError, "Helper cleanup did not finish"):
            self.run_gui(FixtureMachine(cleanup=False))

    def test_obsolete_authorization_choices_remain_failures(self):
        for choice in ("Installed service", "Use on next launch", "In use now:"):
            with self.subTest(choice=choice), self.assertRaises(AssertionError):
                self.run_gui(FixtureMachine(settings="Hardware control\n" + choice))


if __name__ == "__main__":
    unittest.main()
