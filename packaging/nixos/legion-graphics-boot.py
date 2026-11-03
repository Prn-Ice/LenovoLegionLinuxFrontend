#!/usr/bin/env python3
"""Fixed next-boot operations; executable paths are filled by Nix, not callers."""

import fcntl
import json
import math
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import time
import uuid

STATE_DIR = Path("/var/lib/legion-graphics-boot")
CLI = "@cli@"
LIFECYCLE = "@lifecycle@"
MODPROBE = "@modprobe@"
SYSTEMCTL = "@systemctl@"
MODES = ("hybrid", "hybrid-igpu-only")
MAX_REQUEST_AGE_SECONDS = 24 * 60 * 60


class BootGraphics:
    def __init__(self, directory, boot_id, run, drm_root=Path("/sys/class/drm"), now=time.time):
        self.directory = directory
        self.boot_id = boot_id
        self.run = run
        self.drm_root = drm_root
        self.now = now
        self.state_path = directory / "request.json"

    def read(self):
        if not self.state_path.exists():
            return {"phase": "none"}
        with self.state_path.open() as stream:
            text = stream.read(65537)
        if len(text) > 65536:
            raise ValueError("Boot request exceeds size limit")
        state = json.loads(text)
        if not isinstance(state, dict) or state.get("phase") not in (
            "pending", "applying", "failed", "completed", "cancelled"
        ):
            raise ValueError("Invalid boot request state; refusing graphics changes")
        if state["phase"] != "cancelled":
            if state.get("mode") not in MODES:
                raise ValueError("Invalid requested graphics mode")
            uuid.UUID(state["requested_boot_id"])
            requested_at = state.get("requested_at")
            if (type(requested_at) not in (int, float)
                    or not math.isfinite(requested_at)):
                raise ValueError("Invalid boot request timestamp")
        return state

    def write(self, state):
        fd, name = tempfile.mkstemp(prefix=".request-", dir=self.directory)
        try:
            with os.fdopen(fd, "w") as stream:
                json.dump(state, stream, sort_keys=True)
                stream.write("\n")
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(name, self.state_path)
            directory_fd = os.open(self.directory, os.O_RDONLY | os.O_DIRECTORY)
            try:
                os.fsync(directory_fd)
            finally:
                os.close(directory_fd)
        finally:
            if os.path.exists(name):
                os.unlink(name)

    def request(self, mode):
        if mode not in MODES:
            raise ValueError("Only hybrid and hybrid-igpu-only can be queued")
        state = {"phase": "pending", "mode": mode,
                 "requested_boot_id": self.boot_id, "requested_at": self.now()}
        self.write(state)
        return state

    def cancel(self):
        state = self.read()
        if state["phase"] in ("failed", "applying"):
            raise ValueError("A boot transition failed or was interrupted. Queue hybrid for recovery instead.")
        if state["phase"] == "pending":
            state = {"phase": "cancelled"}
            self.write(state)
        return state

    def status(self):
        text = self.run([CLI, "--donotexpecthwmon", "graphics-mode", "status", "--json"])
        status = json.loads(text)
        if not isinstance(status, dict) or status.get("schema_version") != 1:
            raise ValueError("Invalid authoritative graphics status")
        return status

    def check_internal_panel(self):
        internal_connected = False
        for path in self.drm_root.glob("card*-*/status"):
            connected = path.read_text().strip() == "connected"
            internal = "-eDP-" in path.parent.name
            if connected and not internal:
                raise ValueError("Disconnect external displays before requesting iGPU-only")
            internal_connected = internal_connected or (connected and internal)
        if not internal_connected:
            raise ValueError("A connected internal eDP panel is required for iGPU-only")

    @staticmethod
    def validate(status, mode=None):
        if status.get("client_inspection_complete") is not True:
            raise ValueError("Client inspection is incomplete")
        if status.get("active_clients") != []:
            raise ValueError("NVIDIA clients are active; refusing boot transition")
        if mode is not None:
            expected = "detached" if mode == "hybrid-igpu-only" else "attached"
            if (status.get("selected_mode") != mode
                    or status.get("expected_dgpu_state") != expected
                    or status.get("effective_dgpu_state") != expected
                    or status.get("reconciliation") != "settled"):
                raise ValueError("Requested graphics topology did not settle")

    def boot(self):
        state = self.read()
        if state["phase"] in ("failed", "applying"):
            raise ValueError("Previous boot transition failed or was interrupted; queue hybrid for recovery")
        # A rebuild/service restart must never apply a next-boot request live.
        if self.run([SYSTEMCTL, "is-system-running"]).strip() != "starting":
            return {"phase": "deferred", "reason": "Not in system startup; no hardware commands run"}
        pending = state["phase"] == "pending"
        if pending and state["requested_boot_id"] == self.boot_id:
            return {"phase": "deferred", "reason": "Request belongs to this boot; reboot required"}
        if pending:
            # Persist consumption BEFORE any hardware command. A crash/power cut
            # leaves 'applying', which blocks automatic retries on later boots.
            state.update(phase="applying", attempted_boot_id=self.boot_id)
            self.write(state)
        try:
            if pending:
                age = self.now() - state["requested_at"]
                if age < 0 or age > MAX_REQUEST_AGE_SECONDS:
                    raise ValueError("Boot request expired or the clock moved backwards; queue a fresh request")
                users = self.run([SYSTEMCTL, "list-units", "user@*.service",
                                  "--state=active,activating", "--no-legend", "--plain"])
                if users.strip():
                    raise ValueError("A user manager is already running; refusing boot transition")
                before = self.status()
                self.validate(before)
                if before.get("selected_mode") not in MODES:
                    raise ValueError("Boot switching requires an existing Hybrid policy; restore Hybrid in BIOS first")
                if state["mode"] not in before.get("available_modes", []):
                    raise ValueError("Requested mode is not supported by this machine")
                if state["mode"] == "hybrid-igpu-only":
                    self.check_internal_panel()
                self.run([CLI, "--donotexpecthwmon", "graphics-mode", "set", state["mode"], "--json"])
            self.run([CLI, "--donotexpecthwmon", "graphics-mode", "reconcile", "--json"])
            self.run([LIFECYCLE, CLI, "cleanup", MODPROBE])
            if pending:
                after = self.status()
                self.validate(after, state["mode"])
                state.update(phase="completed", final_status=after)
                self.write(state)
            return state
        except Exception as error:
            if pending:
                state.update(phase="failed", error=str(error)[:4096])
                self.write(state)
            raise


def run_command(argv):
    result = subprocess.run(argv, text=True, capture_output=True, timeout=40)
    if result.stdout:
        print(result.stdout, end="", flush=True)
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr, flush=True)
    # is-system-running returns nonzero while starting; its text is authoritative.
    if result.returncode and argv != [SYSTEMCTL, "is-system-running"]:
        raise RuntimeError(f"{argv[0]} exited {result.returncode}")
    return result.stdout


def main():
    if os.geteuid() != 0:
        raise PermissionError("Use the authorized LegionControl1 next-boot methods")
    action, *arguments = sys.argv[1:]
    if action not in ("request", "cancel", "status", "boot"):
        raise ValueError("Unknown next-boot operation")
    if len(arguments) != (1 if action == "request" else 0):
        raise ValueError("Invalid next-boot arguments")
    STATE_DIR.mkdir(mode=0o700, parents=False, exist_ok=True)
    info = STATE_DIR.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != 0 or info.st_mode & 0o077:
        raise PermissionError("Boot request directory must be private and root-owned")
    with (STATE_DIR / "lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        boot_id = Path("/proc/sys/kernel/random/boot_id").read_text().strip()
        helper = BootGraphics(STATE_DIR, boot_id, run_command)
        if action == "request":
            result = helper.request(arguments[0])
        elif action == "cancel":
            result = helper.cancel()
        elif action == "status":
            result = helper.read()
        else:
            result = helper.boot()
        print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"Boot graphics operation failed: {error}", file=sys.stderr)
        sys.exit(1)
