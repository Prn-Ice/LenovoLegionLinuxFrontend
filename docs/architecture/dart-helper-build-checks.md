# Testing a Dart replacement for the control helper

The control helper is the program that makes hardware changes after
administrator approval. This experiment checks two parts of replacing it with
Dart: which system libraries a compiled Dart program needs, and whether Dart
can build the same commands and reject the same invalid values.

The current result: Dart compiles and the command tests pass, but the compiled
program needs system libraries. The AppImage helper currently must run without
loading separate libraries. Packaging and startup still need a working design.

## Check the compiled program

Use the pinned stable SDK in the repository's development shell:

```bash
mkdir -p build
nix develop --command dart compile exe tool/check_dart_helper_build.dart \
  -o build/dart-helper-build-check
build/dart-helper-build-check
```

The tool uses `readelf` to inspect its compiled Linux executable (an ELF file).
It reports the file size, SDK version, program loader, required libraries, and
library search paths. A nonzero exit status means the file fails one or more
requirements for the current AppImage helper.

## What the AppImage helper requires

The AppImage helper must be a 64-bit x86 Linux executable that contains its
libraries, rather than loading them from the host or the AppImage directory.
This is called static linking.

A replacement must also preserve the current startup and permission checks:

- Start a protected, unchangeable copy of the helper (a sealed snapshot).
- Use systemd to manage the temporary service and Polkit for administrator approval.
- Use process handles (pidfds) to track when the app exits.
- Accept only the supported requests over D-Bus, the app's messaging connection.
- Validate inputs and clean up temporary files and processes when finished.

`dart compile exe` includes the Dart runtime, so users do not need a separate
Dart installation. It can still need system libraries. The `readelf` output
shows which libraries this particular build needs. The tool inspects the file;
it does not start the control helper or test approval, hardware writes, or cleanup.

We tested the default `dart compile exe` command. We have not tested alternate
compiler or linker options.

In the actual pinned Ubuntu 22.04 AppImage builder, using Flutter 3.50.0's
bundled stable Dart 3.14.0 on 2026-11-18, the compiled x86-64 test program was
6,749,488 bytes. It reported `/lib64/ld-linux-x86-64.so.2`, `DT_NEEDED`
entries for `libdl.so.2`, `libpthread.so.0`, `libm.so.6`, `libc.so.6`, and
`ld-linux-x86-64.so.2`, plus `DT_RPATH [$ORIGIN/]`. Here, `DT_NEEDED` lists
required libraries, and `DT_RPATH` tells the loader where to search.
`$ORIGIN/` means the executable's directory. The file failed all three checks:
it needs a loader, loads separate libraries, and contains a library search path.
These results come from the actual AppImage build environment; the earlier
Nix build was a separate development check.

Running this tool requires `readelf`. Running it in the Nix development shell
shows that it works with that shell's loader and libraries. It does not prove
that a packaged helper will start on another Linux distribution.

## What needs deciding next

Find a supported way to package and start the Dart helper through the normal
AppImage launch. The default build fails the current library requirements;
we have not shown that every supported build option would fail.

Then decide how Dart will call the Linux functions used for protected program
copies, process tracking, D-Bus file-descriptor transfer, and systemd/Polkit.
Using host libraries or retaining C/C++ code to call those functions would need
an explicit design decision. Neither approach has been approved.

## Building commands without running them

`experiments/dart_helper_commands.dart` checks requested settings and builds
command arguments for the helper's supported operations. It also interprets
exit codes according to which backend command ran. It returns a
`HelperCommand.arguments` list that callers cannot modify and throws
`FormatException` for invalid input. It never executes the commands or opens
the files. For example,
`buildBootLogoCommand(File('/tmp/logo.bmp')).arguments` returns
`['--donotexpecthwmon', 'boot-logo', 'enable', '/tmp/logo.bmp']`.
That path is only a command argument in this experiment. In the real app,
the helper receives file contents, validates them, writes its own private
temporary file, and passes that file's path to the backend.

`test/tool/dart_helper_commands_test.dart` checks:

- All nine numeric settings at their limits and just outside them, using both
  Dart values and incoming text.
- Supported profiles and on/off settings, and complete command arguments for
  toggles, presets, services, and graphics modes.
- Invalid numbers, the 128-byte text limit, both file-size limits, empty file
  contents, and invalid byte values.
- Battery charge limits, file paths with spaces, and each backend's meaning
  for exit statuses 0, 1, 2, 3, and an unknown status.

The expected values come from manual inspection of PR #30 at
`e44b39f537f627f5580255ae9eb28a1734a58fd5` on 2026-11-18; these tests do not
run the C++ implementation for comparison. They check command logic only.
They do not test app-to-helper communication, backend error details, which
error takes priority when cleanup also fails, startup checks, or a packaged
helper.

## Behavior to preserve from PR #30

[PR #30](https://github.com/Prn-Ice/LenovoLegionLinuxFrontend/pull/30)
updated the app for the newer backend and has since merged into main.
The command tests use the PR revision recorded above as their reference.

The replacement helper must preserve these rules:

- Classify generic CLI exit `2` as unavailable and `3` as feature not found;
  map them to `Unavailable` and `NotSupported` only for CLI-backed commands.
- Keep graphics exit `2` and `3` as graphics blocked and pending. Ordinary
  `systemctl` and boot-helper failures remain `CommandFailed`, even when they
  use those numeric statuses.
- Send backend error details back to the app. Preserve the helper's input
  checks, administrator approval, and file and process cleanup.
- Treat variable-size speed-only fan tables as readable but unvalidated and
  read-only. Decode PWM level values through the backend's 0–255 conversion
  and use an explicit RPM ladder; never invent a linear conversion.
- Preserve optional third-fan readings and behavior when a feature is missing.
  Do not turn a missing third fan into a zero reading or a writable control.
- Read power limits back after changing or restoring them. Keep the user's draft
  when firmware clamps, ignores, or fails to report the requested value.
- Refresh charging settings after changes and confirm that the backend reports
  the requested values.

The same exit code can mean different things for different commands.
A future Dart helper must know which command produced it, as PR #30 requires,
and its tests must cover generic CLI, graphics, and systemctl/boot-helper
failures separately.
