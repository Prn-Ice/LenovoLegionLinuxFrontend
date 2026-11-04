# PipeWire X11-bell crash during Plasma logout

A November 3, 2026 Plasma Wayland logout capture with PipeWire 1.6.9 strongly
matches an upstream double-destruction bug in the X11-bell module. It is
separate from graphics detach or hibernate results. DrKonqi's later
`Connection refused` was a secondary forwarding failure after its logout
socket closed.

## Evidence and fix

The journal recorded duplicate X11 I/O error messages followed by `SIGSEGV`.
The saved stack passed through `display_io`, `XPending`,
`x11_io_error_exit_handler`, and `loop_destroy_source`. Installed-module
disassembly confirmed an unconditional source-destruction call at the matching
return address; the source pointer was cleared after the call. A repeated
handler invocation could therefore destroy a null source.

Upstream commit
[`c2fec6c037a191d535319f99d7720232d03f315b`](https://github.com/PipeWire/pipewire/commit/c2fec6c037a191d535319f99d7720232d03f315b)
makes that handler idempotent by guarding destruction with `if (impl->source)`.
The fix is included in
[1.6.10](https://github.com/PipeWire/pipewire/blob/1.6.10/NEWS) and 1.6.11.
A compatible distro package containing that fix, or the exact backport, is the
remediation identified by this evidence. The recorded investigation did not
install or validate it locally.

X11-bell can fail during Xwayland teardown inside a Wayland session; the stack
does not imply an X11 desktop. Automatic PipeWire restart proves process
recovery, not restored playback or capture.

## Validation

After a package fix, record the actual running executable/build and a normal
logout/login time window. Check for new cores, `SEGV`, and automatic restarts,
then verify playback and capture after login. A running service alone is not
proof that logout succeeded without a crash. Investigate persistent DrKonqi
forwarding failures separately from this primary crash.

The [pinned investigation](https://github.com/Prn-Ice/LenovoLegionLinuxFrontend/blob/b83540b6c1ee81e820c479a51b12955ec23a66dc/docs/architecture/pipewire-logout-crash.md)
preserves the exact package, boot/core identifiers, timestamped journal, stack,
binary offsets, and source comparison. The causal match is strong; core-register
inspection and a fixed-version logout/audio test remain unverified.
