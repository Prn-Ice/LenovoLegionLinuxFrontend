# Testing a Dart replacement for the control helper

The control helper is the program that makes hardware changes after
administrator approval. This experiment checks two parts of replacing it with
Dart: which system libraries a compiled Dart program needs, and whether Dart
can build the same commands and reject the same invalid values.

The current result: Dart compiles and the command tests pass. A bundled Dart
runtime and separate compiled app snapshot also pass isolated startup checks
with copied Ubuntu and Nix libraries. Privileged startup still needs a design
that protects every bundled code file. See the
[bundling evaluation](dart-bundled-runtime-evaluation.md) and
[static-runtime evaluation](dart-static-runtime-evaluation.md).

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

The default `dart compile exe` command was tested in both the Ubuntu builder
and the Nix development shell. The additional build options below were tested
in the Nix shell with the same Dart 3.14.0 version.

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

## Other supported build options checked

| Command | Result | Why it does not yet fit the AppImage helper |
| --- | --- | --- |
| `dart compile exe` | One executable containing the app code and Dart runtime. | The runtime needs a loader and five separate system libraries. |
| `dart build cli` | An executable in `bundle/bin` and app code in `bundle/lib/libdartaotcheck_dart_helper_build.so`. | The executable still needs those system libraries. The separate app-code file also falls outside the current single protected executable. |
| `dart compile aot-snapshot` | App code in `helper.aot`, run with `dartaotruntime`. | The separate runtime still needs a loader and system libraries. Splitting the files does not remove those requirements. |

All three commands compiled successfully. The resulting program or runtime
failed the loader, library, and search-path checks, as expected. Local reports
are in `build/dart-helper-build-check.json`, `build/dart-helper-cli/report.json`,
and `build/dart-helper-aot/report.json`. The Ubuntu measurement above remains
the evidence for the production build environment.

To repeat the two additional checks:

```bash
nix develop
dart build cli --target=tool/check_dart_helper_build.dart \
  --output=build/dart-helper-cli
build/dart-helper-cli/bundle/bin/check_dart_helper_build

mkdir -p build/dart-helper-aot
dart compile aot-snapshot tool/check_dart_helper_build.dart \
  -o build/dart-helper-aot/helper.aot
sdk_bin="$(dirname "$(readlink -f "$(command -v dart)")")"
"$sdk_bin/dartaotruntime" build/dart-helper-aot/helper.aot
```

Each inspection command should report the failed requirements and exit with
status 1. For the snapshot command, the inspected executable is
`dartaotruntime`, because that is the program loading the app code.

### Why a compiler flag does not solve this

Dart 3.14.0's verbose `compile exe` help lists target operating system and CPU
options, but no option to statically link its system libraries. The
[compiler source at 3.14.0](https://github.com/dart-lang/sdk/blob/3.14.0/pkg/dart2native/lib/generate.dart)
shows why: it combines the app snapshot with an already-built
`dartaotruntime` through `writeAppendedExecutable`. It does not relink the
runtime's libraries.

The [official compile guide](https://dart.dev/tools/dart-compile) describes
these output formats. The [build guide](https://dart.dev/tools/dart-build)
describes bundling app libraries; that does not make the Dart runtime static.
An [upstream answer about musl](https://github.com/dart-lang/sdk/issues/55782)
points to a separately built Alpine SDK, rather than a compiler switch.
The [request to select a different runtime](https://github.com/dart-lang/sdk/issues/61374)
is still open. Neither source establishes that a fully static runtime can
support all the Linux calls this helper needs.

### Why using host libraries needs a design decision

`control/executable_snapshot.cc` already accepts a dynamic executable when its
loader and library search directories are controlled by root. The AppImage
package has a stricter rule: its helper and cleanup program must be static.
The app starts the privileged service through the host's systemd, outside the
app's bundled library environment. This matters on NixOS as well as Ubuntu.

Removing the static check would not establish a working replacement. A
host-library design must show how the service finds trusted, compatible
libraries on each supported distribution and still starts through the normal
AppImage command. Loading libraries from the user-owned AppImage directory
does not satisfy the existing trust checks.

## Linux API checks

We inspected Dart 3.14.0 and the resolved `dbus` 0.8.0 package, then ran a
small compiled check in the Nix development shell. These checks establish
available APIs; they do not establish a working privileged helper.

### What Dart can already do

- `RawSocket.getRawOption()` calls the operating system's socket-option API.
  Our local Unix-socket check read Linux `SO_PEERCRED` and confirmed that the
  peer's process and user IDs matched the client. This can supply the identity
  check used by `control/portable_control_session.cc`.
- `DynamicLibrary.process()` finds symbols already loaded into the process.
  The compiled check found `getuid`, `memfd_create`, `pidfd_open`, `fcntl`,
  `sendmsg`, `recvmsg`, and `getsockopt`. It called only `getuid`; finding the
  other symbols does not test their use, descriptor ownership, or cleanup.
  Dart FFI therefore does not necessarily require loading another library.
  This result applies to the tested dynamic runtime, not a future static one.
- `RawSocket.readMessage()` and `sendMessage()` support descriptor transfer
  through `SocketControlMessage` and `ResourceHandle`. The `dbus` package
  exposes D-Bus descriptors as `DBusUnixFd`.

The SDK's [`socket.dart`](https://github.com/dart-lang/sdk/blob/3.14.0/sdk/lib/io/socket.dart)
defines these socket and descriptor APIs. Its
[`DynamicLibrary.process()` documentation](https://api.dart.dev/dart-ffi/DynamicLibrary/DynamicLibrary.process.html)
explains symbol lookup. No hardware or privileged service was used in the
compiled check.

### What the current packages do not provide

The resolved `dbus` 0.8.0 source has two gaps for our private helper connection:

- In `lib/src/dbus_auth_server.dart`, `_authenticateExternal()` accepts the
  supplied user ID without checking the socket's peer credentials.
- In `lib/src/dbus_server.dart`, the accepted sockets are private, with no
  public peer-authorization callback. With `messageBus: false`,
  `_processServerMethodCall()` returns `UnknownObject` for application calls;
  this server has no public application-object registration API.

The existing native server checks both process and user IDs and serves only
the approved app session. Using the Dart server unchanged would lose those
checks. Dart's socket APIs can read the credentials, but the package needs
an integration point to use them and dispatch helper requests.

`ResourceHandle` also has no public constructor for an arbitrary Linux file
descriptor. Its constructors wrap Dart-managed resources. That limits direct
use of an FFI-created process handle with `DBusUnixFd`; it does not prove that
Dart cannot transfer such a handle. Calling Linux descriptor operations through
FFI is another possible route, with ownership and cleanup still to design.

These are package-integration gaps, not evidence that the migration requires
new C++ code. An upstream package change, a maintained fork, or a native
integration would each need a concrete proposal before implementation.

## Evaluation and next decision

The user approved evaluating bundled libraries and a custom static runtime.
The [bundling check](dart-bundled-runtime-evaluation.md) ran compiled Dart code
with host libraries hidden. The standard AOT snapshot/runtime pair worked;
the single-executable alternatives failed for the upstream reasons recorded
there. This is evidence for bundled runtime startup, not privileged AppImage
compatibility.

The [static-runtime review](dart-static-runtime-evaluation.md) records the
upstream build options and limits. No fully static runtime was built, so its
feasibility remains unverified.

Prefer developing the bundle design next. The smallest candidate reuses the
existing static starter to protect and prepare all runtime files after approval.
That retains native startup code and adds staging and cleanup responsibilities;
it needs agreement before implementation. A different user launch flow,
host-library exception, package fork, and new native bridge remain unapproved.

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
