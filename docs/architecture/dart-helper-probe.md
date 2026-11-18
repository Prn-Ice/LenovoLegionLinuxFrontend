# Dart helper migration probe

This probe records the Linux executable requirements of a compiled Dart
program. It is evidence for the proposed helper migration, not a replacement
for `legion-portable-control`.

## Run the probe

Use the pinned stable SDK in the repository's development shell:

```bash
mkdir -p build
nix develop --command dart compile exe tool/dart_helper_probe.dart \
  -o build/dart-helper-probe
build/dart-helper-probe
```

The probe inspects its own ELF header and dynamic section with `readelf`. It
reports the executable size, SDK version, ELF interpreter, `DT_NEEDED` entries,
and RPATH/RUNPATH. A nonzero exit status means the compiled file does not meet
the current static-helper checks.

## Current contract and result

The AppImage helper contract requires an x86-64 static ELF with no interpreter,
no shared-library dependencies, and no AppDir library search path. It also
requires the existing sealed executable snapshot, systemd transient unit,
Polkit approval, pidfd lifetime message, typed D-Bus dispatcher, helper-side
validation, and embedded cleanup executable.

`dart compile exe` embeds the Dart runtime, but runtime inclusion does not make
the ELF static. The probe's `readelf` output is the source of truth for the
pinned SDK build. The probe deliberately performs no D-Bus connection,
systemd or Polkit request, pidfd operation, executable snapshot, hardware
write, or helper launch.

The checked command is the default `dart compile exe` command. No linker,
static-runtime, or alternate target options were supplied or evaluated.

In the actual pinned Ubuntu 22.04 AppImage builder, using Flutter 3.50.0's
bundled stable Dart 3.14.0 on 2026-11-18, the compiled x86-64 probe was
6,749,488 bytes. It reported `/lib64/ld-linux-x86-64.so.2`, `DT_NEEDED`
entries for `libdl.so.2`, `libpthread.so.0`, `libm.so.6`, `libc.so.6`, and
`ld-linux-x86-64.so.2`, plus `DT_RPATH [$ORIGIN/]`. It therefore failed all
three static-linkage checks and is not a drop-in replacement for the current
AppImage helper. This is the production-build-environment measurement; the
earlier Nix result is not used as an AppImage requirement.

The probe itself uses `readelf` to inspect its output, so the report command
is an analysis tool rather than evidence that an AppImage can run without host
ELF tooling. The executable runs in the Nix development shell because that
shell supplies the interpreter and libraries; this does not qualify another
distribution or an AppImage launch.

## Migration decision

The demonstrated result is narrower: the default Dart output is dynamically
linked in both tested environments and does not satisfy the current static
helper contract. This probe does not show whether an undocumented linker
change could make it static, and it does not prove that a host-library
packaging exception or a native bridge is necessary. No exception or bridge is
implemented here.

The smallest next proposal is to retain the existing native startup and
cleanup boundary while prototyping only the typed command dispatcher in Dart
against hardware-free fixtures. After that prototype, make a separate,
explicit decision about any documented static-link or host-library packaging
option and about Linux bindings for pidfds, sealed snapshots, D-Bus file
descriptor passing, and systemd/Polkit integration.

## Pure command prototype

`experiments/dart_helper_commands.dart` is the next isolated slice. It ports
the allow-listed feature, toggle, preset, conservation, file, graphics,
service, payload, and exit-classification logic as typed operations. It builds
immutable `HelperCommand.arguments` lists and uses `FormatException` for every
invalid-input path; it never executes a command, opens a file, connects to
D-Bus, or starts a helper. For example,
`buildBootLogoCommand(File('/tmp/logo.bmp')).arguments` returns
`['--donotexpecthwmon', 'boot-logo', 'enable', '/tmp/logo.bmp']`.
That path is only an argv value in this prototype. Production IPC writes a
validated payload to a native private temporary file before passing its path.

`test/tool/dart_helper_commands_test.dart` checks all nine integer feature
ranges and adjacent failures, the profile and boolean allow-lists, every
toggle spelling and flag, presets, services, graphics rejection, malformed
decimal forms, 128-byte UTF-8 boundaries, both payload maxima and max-plus-one,
conservation ordering, file paths with spaces, and every backend category for
exit statuses 0, 1, 2, 3, and an unknown status. The parity source was PR30
head `e44b39f537f627f5580255ae9eb28a1734a58fd5`, inspected read-only on
2026-11-18. This scope does not test D-Bus IPC, backend failure details,
process-status or cleanup precedence, interactive allow-list/startup behavior,
or deployed helper qualification. It is pure-logic evidence, not a replacement
helper or an IPC migration.

## Required compatibility input from PR30

PR30 (`feat/backend-upgrade-compatibility`, open as
https://github.com/Prn-Ice/LenovoLegionLinuxFrontend/pull/30) is a required
input to the migration. Its native changes and Dart contracts are not present
in this probe branch, so they were inspected read-only rather than merged.

The migrated helper must preserve these contracts:

- Classify generic CLI exit `2` as unavailable and `3` as feature not found;
  map them to `Unavailable` and `NotSupported` only for CLI-backed commands.
- Keep graphics exit `2` and `3` as graphics blocked and pending. Ordinary
  `systemctl` and boot-helper failures remain `CommandFailed`, even when they
  use those numeric statuses.
- Retain backend error details in the typed D-Bus error response and preserve
  helper-side validation, operation cleanup, and authorization boundaries.
- Treat variable-size speed-only fan tables as readable but unvalidated and
  read-only. Decode PWM level values through the backend's 0–255 conversion
  and use an explicit RPM ladder; never invent a linear conversion.
- Preserve optional third-fan telemetry and absent-capability behavior. Do not
  turn a missing third fan into a zero reading or a writable control.
- Verify power-limit readback after writes and rollback. Keep a requested draft
  when firmware clamps, ignores, or fails to report the requested value.
- Keep charging refresh/readback and the existing typed operation contracts;
  these are part of the Dart-facing behavior even though they are not startup
  mechanics.

These requirements mean a future Dart dispatcher cannot classify exit status
globally. It needs the command context that PR30 added to the native runtime,
and its tests must cover generic CLI, graphics, and systemctl/boot-helper
failures separately.
