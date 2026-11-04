# PipeWire X11-bell crash during Plasma logout

PipeWire 1.6.9 crashed during Plasma Wayland logout on November 3, 2026.
The logs and binary inspection strongly match a known X11-bell
double-destruction bug.

## Evidence and fix

The journal recorded duplicate X11 I/O error messages followed by `SIGSEGV`.
The saved stack passed through `display_io`, `XPending`,
`x11_io_error_exit_handler`, and `loop_destroy_source`. Installed-module
disassembly confirmed an unconditional source-destruction call at the matching
return address; the source pointer was cleared after the call. A repeated
handler invocation could therefore destroy a null source.

DrKonqi's later `Connection refused` was a secondary forwarding failure after
its logout socket closed.

Upstream commit
[`c2fec6c037a191d535319f99d7720232d03f315b`](https://github.com/PipeWire/pipewire/commit/c2fec6c037a191d535319f99d7720232d03f315b)
makes that handler idempotent by guarding destruction with `if (impl->source)`.
The fix is included in
[1.6.10](https://github.com/PipeWire/pipewire/blob/1.6.10/NEWS) and 1.6.11.
Use a compatible distribution package containing the fix, or backport the
commit. The fix has not been tested locally.

This X11-bell bug can also occur in a Wayland session when Xwayland closes.

## Validation

After updating, record the running PipeWire version, executable/build, and the
time of a normal logout and login. Check for new cores, `SEGV`, and automatic
restarts, then verify playback and capture after login. Investigate persistent
DrKonqi forwarding failures separately from this primary crash.

The [pinned investigation](https://github.com/Prn-Ice/LenovoLegionLinuxFrontend/blob/b83540b6c1ee81e820c479a51b12955ec23a66dc/docs/architecture/pipewire-logout-crash.md)
preserves the exact package, boot/core identifiers, timestamped journal, stack,
binary offsets, and source comparison. Still to check: core registers and
logout/audio behavior with the fix installed.
