#!/usr/bin/env python3
"""Real request persistence and transitions with hardware/systemd calls faked."""

import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
SOURCE = Path(__file__).resolve().parents[1] / "packaging/nixos/legion-graphics-boot.py"
SPEC = importlib.util.spec_from_file_location("graphics_boot", SOURCE)
boot = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(boot)
OLD_BOOT = "11111111-1111-4111-8111-111111111111"
NEW_BOOT = "22222222-2222-4222-8222-222222222222"


def graphics(mode="hybrid", **changes):
    effective = "detached" if mode == "hybrid-igpu-only" else "attached"
    result = dict(schema_version=1, selected_mode=mode, expected_dgpu_state=effective,
                  effective_dgpu_state=effective, reconciliation="settled",
                  client_inspection_complete=True, active_clients=[],
                  available_modes=["hybrid", "hybrid-igpu-only"])
    result.update(changes)
    return result


class BootTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="legion-boot-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.calls = []
        self.manager = "starting"
        self.users = ""
        self.before = graphics()
        self.after = graphics("hybrid-igpu-only")
        self.failure = None
        self.status_count = 0
        drm = self.root / "drm"
        (drm / "card0-eDP-1").mkdir(parents=True)
        (drm / "card0-eDP-1/status").write_text("connected\n")
        self.clock = 100000
        self.helper = boot.BootGraphics(self.root, OLD_BOOT, self.run_command, drm,
                                        now=lambda: self.clock)

    def run_command(self, argv):
        self.calls.append(argv)
        if argv == [boot.SYSTEMCTL, "is-system-running"]:
            return self.manager
        if argv[0] == boot.SYSTEMCTL:
            return self.users
        if argv[0] == boot.CLI and "status" in argv:
            result = self.before if self.status_count == 0 else self.after
            self.status_count += 1
            return json.dumps(result)
        # Real backend performs its second inspection inside set. Simulate its
        # refusal if a new client appears after the helper's initial inspection.
        if self.failure == "set" and "set" in argv:
            raise RuntimeError("backend refused newly opened NVIDIA client")
        if self.failure == "cleanup" and argv[0] == boot.LIFECYCLE:
            raise RuntimeError("module remains busy")
        return "{}"

    def queue(self, mode="hybrid-igpu-only"):
        self.helper.boot_id = OLD_BOOT
        self.helper.request(mode)
        self.helper.boot_id = NEW_BOOT

    def assert_no_selection(self):
        self.assertFalse(any("set" in command for command in self.calls))

    def test_queue_and_cancel_have_no_hardware_calls(self):
        state = self.helper.request("hybrid-igpu-only")
        self.assertEqual(state["phase"], "pending")
        self.assertEqual(self.helper.cancel()["phase"], "cancelled")
        self.assertEqual(self.calls, [])
        self.assertEqual(self.helper.state_path.stat().st_mode & 0o777, 0o600)

    def test_modes_restricted(self):
        for mode in ("discrete", "hybrid-auto", "", "../hybrid", "hybrid;reboot"):
            with self.subTest(mode=mode), self.assertRaises(ValueError):
                self.helper.request(mode)
        self.assertEqual(self.calls, [])

    def test_same_boot_never_selects(self):
        self.helper.request("hybrid-igpu-only")
        self.assertEqual(self.helper.boot()["phase"], "deferred")
        self.assertEqual(self.helper.read()["phase"], "pending")
        self.assertEqual(len(self.calls), 1)

    def test_live_activation_never_runs_hardware(self):
        self.queue()
        for state in ("running", "degraded", "maintenance", "stopping", "unknown"):
            self.manager = state
            self.assertEqual(self.helper.boot()["phase"], "deferred")
        self.assertTrue(all(command[0] == boot.SYSTEMCTL for command in self.calls))
        self.assertEqual(self.helper.read()["phase"], "pending")

    def test_request_applied_once_and_verified(self):
        self.queue()
        def checked_run(argv):
            if argv[0] == boot.CLI:
                self.assertEqual(self.helper.read()["phase"], "applying")
            return self.run_command(argv)
        self.helper.run = checked_run
        self.assertEqual(self.helper.boot()["phase"], "completed")
        self.assertEqual(self.helper.read()["final_status"], self.after)
        selected = [command for command in self.calls if "set" in command]
        self.assertEqual(len(selected), 1)
        self.helper.run = self.run_command
        self.helper.boot()
        self.assertEqual(len([command for command in self.calls if "set" in command]), 1)

    def test_user_manager_blocks_before_hardware(self):
        self.queue()
        self.users = "user@1000.service loaded active running"
        with self.assertRaisesRegex(ValueError, "user manager"):
            self.helper.boot()
        self.assertTrue(all(command[0] == boot.SYSTEMCTL for command in self.calls))
        self.assertEqual(self.helper.read()["phase"], "failed")

    def test_stale_or_future_request_blocks_before_hardware(self):
        for delta in (boot.MAX_REQUEST_AGE_SECONDS + 1, -1):
            with self.subTest(delta=delta):
                self.queue()
                self.clock += delta
                with self.assertRaisesRegex(ValueError, "expired"):
                    self.helper.boot()
                self.assertTrue(all(command[0] == boot.SYSTEMCTL for command in self.calls))
                self.assertEqual(self.helper.read()["phase"], "failed")

    def test_external_display_blocks_ejection(self):
        self.queue()
        (self.helper.drm_root / "card1-HDMI-A-1").mkdir()
        (self.helper.drm_root / "card1-HDMI-A-1/status").write_text("connected\n")
        with self.assertRaisesRegex(ValueError, "external displays"):
            self.helper.boot()
        self.assert_no_selection()

    def test_missing_internal_panel_blocks_ejection(self):
        self.queue()
        (self.helper.drm_root / "card0-eDP-1/status").write_text("disconnected\n")
        with self.assertRaisesRegex(ValueError, "internal eDP"):
            self.helper.boot()
        self.assert_no_selection()

    def test_clients_or_incomplete_inspection_block(self):
        for changes in ({"active_clients": [{"pid": 42}]},
                        {"client_inspection_complete": False},
                        {"active_clients": None}):
            with self.subTest(changes=changes):
                self.queue()
                self.status_count = 0
                self.before = graphics(**changes)
                with self.assertRaises(ValueError):
                    self.helper.boot()
                self.assert_no_selection()

    def test_unsupported_or_discrete_policy_blocks(self):
        for changes in ({"available_modes": ["hybrid"]}, {"selected_mode": "discrete"}):
            with self.subTest(changes=changes):
                self.queue()
                self.status_count = 0
                self.before = graphics(**changes)
                with self.assertRaises(ValueError):
                    self.helper.boot()
                self.assert_no_selection()

    def test_late_client_backend_refusal_is_not_retried(self):
        self.queue()
        self.failure = "set"
        with self.assertRaisesRegex(RuntimeError, "newly opened"):
            self.helper.boot()
        count = len(self.calls)
        with self.assertRaisesRegex(ValueError, "Previous boot transition"):
            self.helper.boot()
        self.assertEqual(len(self.calls), count)
        with self.assertRaisesRegex(ValueError, "recovery"):
            self.helper.cancel()

    def test_cleanup_failure_blocks_success(self):
        self.queue()
        self.failure = "cleanup"
        with self.assertRaisesRegex(RuntimeError, "module remains busy"):
            self.helper.boot()
        self.assertEqual(self.helper.read()["phase"], "failed")

    def test_final_status_must_match_requested_topology(self):
        self.queue()
        self.after = graphics()
        with self.assertRaisesRegex(ValueError, "did not settle"):
            self.helper.boot()
        self.assertEqual(self.helper.read()["phase"], "failed")

    def test_interrupted_attempt_requires_explicit_recovery(self):
        self.queue()
        state = self.helper.read()
        state["phase"] = "applying"
        self.helper.write(state)
        with self.assertRaises(ValueError):
            self.helper.boot()
        self.assertEqual(self.calls, [])
        self.helper.request("hybrid")
        self.helper.boot_id = "33333333-3333-4333-8333-333333333333"
        self.after = graphics()
        self.assertEqual(self.helper.boot()["phase"], "completed")

    def test_no_request_preserves_normal_reconcile_cleanup(self):
        self.assertEqual(self.helper.boot()["phase"], "none")
        self.assertEqual(self.calls, [
            [boot.SYSTEMCTL, "is-system-running"],
            [boot.CLI, "--donotexpecthwmon", "graphics-mode", "reconcile", "--json"],
            [boot.LIFECYCLE, boot.CLI, "cleanup", boot.MODPROBE],
        ])

    def test_invalid_state_refuses_before_commands(self):
        for text in ("not-json", "[]", '{"phase":"unknown"}', "x" * 65537):
            with self.subTest(text=text[:30]):
                self.helper.state_path.write_text(text)
                with self.assertRaises((ValueError, KeyError)):
                    self.helper.boot()
        self.assertEqual(self.calls, [])


if __name__ == "__main__":
    unittest.main()
