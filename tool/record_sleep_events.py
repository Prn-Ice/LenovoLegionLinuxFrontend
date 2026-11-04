#!/usr/bin/env python3
"""Save journal events for the next naturally occurring sleep problem."""

from datetime import datetime
import json
import os
from pathlib import Path
import subprocess
import sys

MAX_BYTES = 8 * 1024 * 1024
BACKUPS = 3
UNITS = (
    "systemd-suspend.service", "systemd-hibernate.service",
    "systemd-suspend-then-hibernate.service", "systemd-logind.service",
    "legion-graphics-reconcile.service",
)


def journal_command():
    matches = ["_TRANSPORT=kernel"]
    for unit in UNITS:
        matches.extend(["+", f"_SYSTEMD_UNIT={unit}"])
    matches.extend(["+", "SYSLOG_IDENTIFIER=org_kde_powerdevil",
                    "+", "_COMM=kwin_wayland"])
    return ["journalctl", "--boot", "--since=-30min", "--follow",
            "--output=json", "--no-pager", *matches]


def keep_event(event):
    # libddcutil logs every bus change; retain its sleep and failure messages,
    # rather than letting routine polling overwrite the useful history.
    if event.get("SYSLOG_IDENTIFIER") == "org_kde_powerdevil":
        message = str(event.get("MESSAGE", "")).lower()
        return any(word in message for word in (
            "sleep", "suspend", "hibernat", "error", "fail", "outputs",
            "button", "lid", "idle", "battery", "critical",
        ))
    return True


class SavedEvents:
    def __init__(self, directory, max_bytes=MAX_BYTES):
        self.directory = directory
        self.path = directory / "events.jsonl"
        self.max_bytes = max_bytes

    def append(self, event):
        data = (json.dumps(event, ensure_ascii=True) + "\n").encode()
        if len(data) > self.max_bytes:
            raise ValueError("Journal event exceeds the file size limit")
        if self.path.exists() and self.path.stat().st_size + len(data) > self.max_bytes:
            for index in range(BACKUPS, 0, -1):
                source = self.path if index == 1 else self.directory / f"events.{index - 1}.jsonl"
                target = self.directory / f"events.{index}.jsonl"
                if source.exists():
                    os.replace(source, target)
        with self.path.open("ab") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        # Persist creation/rotation too, not just the contents of the file.
        fd = os.open(self.directory, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)


def main():
    if len(sys.argv) != 1:
        raise ValueError("Usage: python3 ~/legion-record")
    os.umask(0o077)
    root = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state")))
    directory = root / "legion-sleep-recorder" / datetime.now().astimezone().strftime("%Y%m%d-%H%M%S-%f")
    directory.mkdir(parents=True, mode=0o700)
    saved = SavedEvents(directory)
    saved.append({
        "recorder_started": datetime.now().astimezone().isoformat(),
        "boot_id": Path("/proc/sys/kernel/random/boot_id").read_text().strip(),
        "generation": str(Path("/run/current-system").resolve()),
        "limitation": "User recorder freezes during sleep; no physical power-off proof",
    })
    print(f"Saving sleep/display events to {directory}", flush=True)
    print("Leave this terminal open. Ctrl+C stops recording. No sleep or settings changes requested.", flush=True)
    print("Up to four 8 MiB files are kept for this run. Logs may contain process/device details.", flush=True)
    process = subprocess.Popen(journal_command(), stdout=subprocess.PIPE, text=True)
    count = 0
    try:
        for line in process.stdout:
            event = json.loads(line)
            if keep_event(event):
                saved.append(event)
                count += 1
                if count == 1:
                    print("Journal events are being saved.", flush=True)
        result = process.wait()
        if result:
            raise RuntimeError(f"journalctl stopped with exit {result}; check journal permissions")
        if not count:
            raise RuntimeError("No journal events received; access or capture is unverified")
    except KeyboardInterrupt:
        print("\nStopping recorder.", flush=True)
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        process.stdout.close()
        saved.append({"recorder_stopped": datetime.now().astimezone().isoformat(),
                      "saved_events": count})
        print(f"Logs retained: {directory}", flush=True)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"Recorder failed: {error}", file=sys.stderr)
        sys.exit(1)
