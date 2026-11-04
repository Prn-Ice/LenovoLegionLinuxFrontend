# PipeWire X11-bell crash during Plasma logout

Issue: `lllf-04d`. Read-only investigation: 2026-11-04.

## Conclusion

The saved crash strongly matches an upstream bug fixed in **PipeWire 1.6.10**:
the X11-bell I/O error handler destroys its event source twice when the X
connection disappears. The installed 1.6.9 binary lacks the upstream null guard.
Prefer a compatible stable package containing the fix (1.6.10 minimum; 1.6.11
also contains it), or a distro backport of the exact upstream patch. Neither
upgrade nor logout/audio validation was performed here.

DrKonqi's `Connection refused` is a secondary crash-forwarding failure: its
user socket had already closed during logout. Clearing that failed unit would
not fix PipeWire.

## Local evidence

All observations below came from existing journal/core metadata and an
unprivileged read of the installed binary/configuration. No service restart,
logout, playback, hardware access, host configuration change, or external report
publication was performed. The core was not extracted or debugged.

- Boot: `3a1b0a31b6fc49549318b5a38ddb8ae3`.
- Crash: 2026-11-03 **17:54:29 WAT**, PID/TID 2342, `SIGSEGV`, `SEGV_MAPERR`.
- Executable:
  `/nix/store/wfi1i34azyilqvh1q74fbr0p5rc78fmq-pipewire-1.6.9/bin/pipewire`.
- User unit: `pipewire.service`, UID 1000.
- Preserved core (reported present, 440.9K on disk):
  `/var/lib/systemd/coredump/core.pipewire.1000.3a1b0a31b6fc49549318b5a38ddb8ae3.2342.1793724869000000.zst`.

Journal sequence, in local time:

| Time | Evidence |
| --- | --- |
| 17:54:23 | Plasma LogoutPrompt starts. |
| 17:54:28 | KDE Plasma Workspace begins stopping. |
| 17:54:29 | `Closed Socket to launch DrKonqi for a systemd-coredump crash.` |
| 17:54:29 | KDE Wayland Compositor begins stopping. |
| 17:54:29 | PID 2342 logs `X11 I/O error handler called on display :0` and `X11 display (:0) has encountered a fatal I/O error` **twice each**. |
| 17:54:29 | Kernel reports `segfault at 30`, instruction in `libspa-support.so + 0x8d6c`. |
| 17:54:29 | systemd records PipeWire `status=11/SEGV`, result `core-dump`. |
| 17:54:29 | DrKonqi processor names this same PID/core, logs `Connection refused`, exits 1. |
| 17:54:29 | PipeWire restart counter becomes 1; PipeWire and WirePlumber start again. |
| 17:54:31 | Compositor stops; SDDM closes the user session and starts the greeter. |

Relevant saved stack, caller-to-callee:

```text
pw_main_loop_run
  loop_iterate
    display_io                         libpipewire-module-x11-bell.so + 0x25e9
      XPending
        _XEventsQueued
          _XIOError
            x11_io_error_exit_handler libpipewire-module-x11-bell.so + 0x2ac2
              loop_destroy_source     libspa-support.so + 0x8d6c
```

This is an X11 connection error inside a Wayland session, consistent with
Xwayland teardown; it does not imply that the session itself was X11. The
journal does not establish the precise X server termination mechanism.

The automatic service restart proves process recovery only. Subsequent
WirePlumber logs include transient ALSA device-open errors and later endpoint
registration; neither is a listening/capture test. Audio recovery remains
unverified.

## Source and binary comparison

1. [1.6.9 module source](https://github.com/PipeWire/pipewire/blob/1.6.9/src/modules/module-x11-bell.c)
   calls `pw_loop_destroy_source(impl->loop, impl->source)` unconditionally,
   sets `impl->source = NULL`, and schedules module destruction. A second call
   for that display can therefore pass NULL into source destruction.
2. [1.6.9 loop source](https://github.com/PipeWire/pipewire/blob/1.6.9/spa/plugins/support/loop.c)
   dereferences the source's containing structure in `loop_destroy_source`;
   it does not accept a NULL source.
3. Installed module disassembly confirms that this is not merely a version-label
   assumption: at `0x2ab4` it loads `impl->source` into `%rsi`, then calls the
   destroy method at `0x2ac0` without testing that source. Return address `0x2ac2`
   exactly matches the core stack. At `0x2ac6` it clears the source pointer.
4. Upstream commit
   [`c2fec6c037a191d535319f99d7720232d03f315b`](https://github.com/PipeWire/pipewire/commit/c2fec6c037a191d535319f99d7720232d03f315b),
   committed 2026-10-20, is titled **“module-x11-bell: make the X11 I/O error
   handler idempotent”**. Its message reports a crash during aerynOS GDM teardown.
   Its entire functional change guards destruction:

   ```c
   /* _XIOError() can be entered more than once for the same dead
    * connection, so only destroy the source while it is still valid */
   if (impl->source) {
       pw_loop_destroy_source(impl->loop, impl->source);
       impl->source = NULL;
   }
   ```

5. [1.6.10 release notes](https://github.com/PipeWire/pipewire/blob/1.6.10/NEWS)
   (2026-10-22) explicitly say: “Fix a potential crash in the X11 module because
   error handlers can be called twice.” The release is described as API/ABI
   compatible with previous 1.6.x releases. Both the
   [1.6.10 source](https://github.com/PipeWire/pipewire/blob/1.6.10/src/modules/module-x11-bell.c)
   and [1.6.11 source](https://github.com/PipeWire/pipewire/blob/1.6.11/src/modules/module-x11-bell.c)
   contain the guard; 1.6.11 was released 2026-10-29.

Together, the duplicate handler logs, fault location, binary call site, and
upstream fix provide a strong causal match. Core register inspection and an
actual fixed-version logout test would be needed to turn this into a locally
verified fix.

The upstream GitLab commit URL returned an Anubis challenge during this
investigation. Source, commit metadata/diff, and tagged release notes were read
from the PipeWire GitHub mirror. Context7 `/pipewire/pipewire` confirmed the
configuration condition semantics; tagged source and installed files supplied
the version-specific evidence. Older bell/libcanberra crashes fixed in 2023
are different paths and are not the basis of this recommendation.

## Safe remediation path for the parent

1. Review a NixOS package update to a compatible stable version containing the
   guard, or backport the exact commit to 1.6.9. Confirm the actual selected
   package and running executable, not just the shell's `pipewire --version`.
   No NixOS evaluation, build, activation, or package change was done here.
2. If a package fix cannot be scheduled, a narrowly scoped temporary mitigation
   is disabling the optional X11-bell module at its next normal startup. This
   removes PipeWire's X11 bell sound interception. The installed
   `share/pipewire/pipewire.conf` lines 220–230 explicitly gate it on
   `condition = [ { module.x11.bell = !false } ]`. A proposed user drop-in is
   `~/.config/pipewire/pipewire.conf.d/disable-x11-bell.conf`:

   ```text
   context.properties = {
       module.x11.bell = false
   }
   ```

   This was **not written or applied**. Before using it, inspect effective
   configuration for unconditional duplicate module loads or property overrides.
   Removing only that drop-in reverses the mitigation on a subsequent startup.
   Prefer the package fix when bell behavior should be preserved.
3. Keep the existing crash evidence. Do not treat a DrKonqi failed-state reset
   as remediation or reset it merely to make validation look clean.

## Remaining validation and report path

- Parent/user schedules a normal logout/login after the selected package fix.
  Record the package, running executable, boot ID, and test time window.
- Confirm no new PipeWire core or `SEGV` in that window, and inspect service
  restarts. A service that is running after an automatic crash restart is not
  sufficient evidence of success.
- Verify normal playback and capture after login; check expected sinks/sources
  and device reconnection. Repeat normal logout/login to exercise the teardown
  path. These are pending user-session tests, not actions taken here.
- If the same stack recurs with the guard demonstrably present, prepare an
  issue at [PipeWire's upstream tracker](https://gitlab.freedesktop.org/pipewire/pipewire/-/issues),
  referencing the commit and release notes. Suggested title:
  `x11-bell: repeated X11 I/O error during Plasma logout crashes in loop_destroy_source`.
  Include the filtered timeline, exact package/build identity, stack, session
  type, effective bell configuration, and test outcome. Review identifying
  metadata before sharing; do not upload the raw core by default. No upstream
  issue number was established and no report was published.
- If forwarding still fails independently after the primary crash is resolved,
  investigate DrKonqi's logout/socket lifecycle separately. The current evidence
  establishes socket closure and refusal, not a separate DrKonqi fix.

## Read-only checks used

```sh
coredumpctl info 2342
journalctl -b 3a1b0a31b6fc49549318b5a38ddb8ae3 \
  --since '2026-11-03 17:54:20' --until '2026-11-03 17:54:45' --no-pager
journalctl -b 3a1b0a31b6fc49549318b5a38ddb8ae3 \
  --since '2026-11-03 17:54:20' --until '2026-11-03 17:54:31' \
  --grep 'X11|Xwayland|X connection|pipewire|DrKonqi|drkonqi|Stopping KDE|logout|Logout' \
  --no-pager
objdump -d --disassemble=x11_io_error_exit_handler \
  /nix/store/wfi1i34azyilqvh1q74fbr0p5rc78fmq-pipewire-1.6.9/lib/pipewire-0.3/libpipewire-module-x11-bell.so
```

Documentation-only change. No application tests or hardware tests were run.
Parent owns issue status decisions and commit/push.
