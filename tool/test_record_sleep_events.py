#!/usr/bin/env python3
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("recorder", Path(__file__).with_name("record_sleep_events.py"))
recorder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(recorder)


class RecorderTests(unittest.TestCase):
    def test_filters_polling_not_sleep_or_errors(self):
        def event(message):
            return {"SYSLOG_IDENTIFIER": "org_kde_powerdevil", "MESSAGE": message}
        self.assertFalse(recorder.keep_event(event("prop_devname: /dev/i2c-20")))
        for text in ("PrepareForSleep(true)", "There are no outputs", "Failed", "Idle timeout", "Power button"):
            self.assertTrue(recorder.keep_event(event(text)))
        self.assertTrue(recorder.keep_event({"MESSAGE": "kernel message"}))

    def test_saved_json_private_and_rotation_bounded(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            old = os.umask(0o077)
            try:
                saved = recorder.SavedEvents(directory, max_bytes=45)
                for index in range(20):
                    saved.append({"index": index, "message": "evidence"})
            finally:
                os.umask(old)
            files = list(directory.glob("*.jsonl"))
            self.assertEqual(len(files), 4)
            self.assertEqual(json.loads(saved.path.read_text())["index"], 19)
            for path in files:
                self.assertLessEqual(path.stat().st_size, 45)
                self.assertEqual(path.stat().st_mode & 0o077, 0)
            with self.assertRaises(ValueError):
                saved.append({"message": "x" * 100})

    def test_command_only_reads_journal(self):
        command = recorder.journal_command()
        self.assertEqual(command[0], "journalctl")
        self.assertIn("--follow", command)
        self.assertIn("_TRANSPORT=kernel", command)
        self.assertIn("_COMM=kwin_wayland", command)
        self.assertNotIn("sudo", command)

    def test_process_saves_events_and_reports_journal_failure(self):
        script = Path(__file__).with_name("record_sleep_events.py").resolve()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            journal = root / "journalctl"
            journal.write_text(
                f'#!{sys.executable}\n'
                'import os\n'
                'print(\'{"MESSAGE":"PM: hibernation entry","_TRANSPORT":"kernel"}\', flush=True)\n'
                'raise SystemExit(int(os.environ.get("FAKE_JOURNAL_EXIT", "0")))\n'
            )
            journal.chmod(0o700)
            for code in (0, 1):
                state = root / f"state-{code}"
                env = dict(os.environ, PATH=f"{root}:{os.environ['PATH']}",
                           XDG_STATE_HOME=str(state), FAKE_JOURNAL_EXIT=str(code))
                result = subprocess.run([sys.executable, str(script)], env=env,
                                        text=True, capture_output=True, timeout=5)
                self.assertEqual(result.returncode, code, result.stderr)
                self.assertIn("Journal events are being saved", result.stdout)
                logs = list(state.glob("legion-sleep-recorder/*/events.jsonl"))
                self.assertEqual(len(logs), 1)
                events = [json.loads(line) for line in logs[0].read_text().splitlines()]
                self.assertIn("recorder_started", events[0])
                self.assertEqual(events[1]["MESSAGE"], "PM: hibernation entry")
                self.assertEqual(events[-1]["saved_events"], 1)
                if code:
                    self.assertIn("journalctl stopped with exit 1", result.stderr)


if __name__ == "__main__":
    unittest.main()
