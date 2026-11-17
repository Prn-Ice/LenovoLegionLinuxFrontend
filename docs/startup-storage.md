# Startup storage recovery: deferred

`lib/main.dart` opens the Hive boxes before calling `runApp`. If storage cannot
open, the app can leave a black window. The observed desktop failure was a lock
error while another AppImage instance was running. Close the existing instance
before launching another copy. Do not delete lock files or bypass locking.

## Why the retry implementation was rejected

On 17 November 2026, a proposed recovery screen added Retry and Close actions
and cleanup of boxes opened during a failed attempt. Review found that its
two-process test stopped the lock owner before attempting the competing open;
it did not test contention.

The corrected test used the pinned Flutter 3.50 environment and Hive CE 2.23.3:

1. Start a separate Dart process, initialize Hive in a temporary directory, and
   open `sensor_records`. Wait for its explicit `locked` message.
2. In the test process, open the same box while the owner is still alive.
   Expect `FileSystemException` from the lock attempt.
3. Before stopping the owner, check that `sensor_records.lock` still exists.
   **This assertion failed: Hive had removed the lock file.**

In Hive CE 2.23.3, `lib/src/hive_impl.dart` catches the failed initialization and
calls `newBox.close()`. In `lib/src/backend/vm/storage_backend_vm.dart`,
`initialize()` acquires the lock at line 126, but `_closeInternal()` deletes the
lock path at line 309 even when acquisition failed. This removes the pathname
of the other process's lock. Retrying could open a new lock file instead of
contending with the original owner's lock. No data corruption was observed or
tested; safe exclusive access was not established.

The pub.dev API reported 2.23.3 as the latest stable release on that date. No
dependency override, fork, or application-specific lock scheme was introduced.
The proposed startup code was removed. The app still has its original startup
behavior; visible recovery and safe retry remain deferred in `lllf-wzb`.

## Retained evidence

- `/tmp/opencode/startup-lock-verification.log`, SHA256
  `dbf762de70b1bfecb83e0fd4c01cddef5658ddac82302051bf61475719e05e7f`
- `/tmp/opencode/startup-recovery-rejected.patch`, SHA256
  `2c54dad8fa493ca9e2a5e5bdddb34fc1111d506b637021f8c1350d812db9ff03`
- `/tmp/opencode/startup-recovery-rejected-files.tar.gz`, SHA256
  `c1d3ee716437557e01b1eef8f6d34254ad31cdfc7076c4aa150856458ccb47ff`

The archive contains the rejected implementation and test fixtures, not a
release input. The reproduction sequence and source diagnosis above remain
usable if those local files expire.

## Resume when a supported fix is available

First verify that a failed competing open preserves the owner's lock and that
another attempt still fails while that owner is alive. Then stop the owner and
verify successful retry with the stored values intact. Only after those checks
pass should startup recovery be integrated and tested through the real app.

This dependency issue is separate from the [native shutdown crash](linux-shutdown.md).
