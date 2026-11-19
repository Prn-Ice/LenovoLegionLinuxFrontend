# Bundling the Dart helper's runtime

The bundled runtime passed isolated startup checks with Ubuntu 22.04 and Nix
glibc libraries. The approved native-starter prototype also passed privileged
startup and cleanup checks in a disposable NixOS VM. Normal AppImage launch
with a Dart helper remains unverified.

The working layout uses Dart's standard ahead-of-time snapshot format:

```text
bundle/
  dartaotruntime       Dart's prebuilt runtime
  runtime-check.aot   Compiled Dart app code
  lib/
    ld-linux-x86-64.so.2
    libc.so.6
    libm.so.6
    libdl.so.2
    libpthread.so.0
```

The loader starts the runtime, which reads the compiled app code:

```bash
/bundle/lib/ld-linux-x86-64.so.2 --inhibit-cache \
  --library-path /bundle/lib \
  /bundle/dartaotruntime /bundle/runtime-check.aot
```

This is a test command inside an isolated filesystem, not a proposed user
launcher. A shipped AppImage would contain these files and start them internally.
Users would not install Dart.

## What ran

On 2026-11-19, `tool/test_bundled_dart_runtime.sh` compiled
`experiments/check_bundled_dart_runtime.dart` with the pinned Dart 3.14.0 SDK.
It copied the runtime and five glibc files into a bundle, then ran it through
Bubblewrap with an empty environment and filesystem. Only the bundle,
`/proc`, `/dev`, and temporary storage were visible. Host library directories,
the Dart SDK, the system bus, and networking were absent.

The host was NixOS 26.11, Linux 7.3.4. Two library sets were tested:

- Nix glibc `2.44-57`, copied from the compiler's interpreter directory.
- Ubuntu 22.04 glibc `2.35-0ubuntu3.18`, extracted from the official security
  archive. The package checksum matched Ubuntu's HTTPS package index.

Both sets produced these results:

| Check | Result |
| --- | --- |
| Explicit loader starts a `dart compile exe` executable | Exit 255; Dart printed VM usage. |
| `patchelf` changes that executable's interpreter and library path | Exit 255; Dart printed VM usage. |
| Explicit loader starts `dartaotruntime` with an AOT snapshot | Exit 0; file read/write and socket peer PID/UID checks passed. |
| All file-backed memory mappings come from the bundle | Passed; no host library mappings appeared. |
| Hide bundled `libm.so.6` | Exit 127; loader reported the missing library. |

The Ubuntu runtime, snapshot, and five library files totalled 10,193,649 bytes
before compression. This size describes the diagnostic program, not the final
helper or the increase in AppImage size.

The diagnostic also inspected FFI symbols without opening another library.
Ubuntu's glibc exposed `getuid`, `memfd_create`, `fcntl`, `sendmsg`, `recvmsg`,
`getsockopt`, and `syscall`, but no `pidfd_open` wrapper. The Nix libraries
exposed all of them. Only `getuid` was called through FFI. Existing native
process tracking calls `syscall(SYS_pidfd_open, ...)`; equivalent Dart bindings
still need implementation and tests.

## Why the single executable failed

Dart 3.14.0 finds its appended app snapshot through `/proc/self/exe`. Explicitly
starting it through the loader makes that path identify the loader instead.
Changing a compiled executable with `patchelf` can also invalidate the appended
snapshot offsets. These are the two cases discussed in
[Dart issue #50926](https://github.com/dart-lang/sdk/issues/50926).

The upstream recommendation is to distribute the AOT snapshot and runtime as
separate files when this executable format breaks. Our successful check follows
that format. It uses the standard runtime supplied by the pinned Nix SDK; it
does not rebuild Dart or modify SDK source.

## Protected-startup prototype

The current native startup protects one sealed executable before asking for
administrator approval. `control/portable_bootstrap.cc` passes that descriptor
to systemd and starts `/proc/self/fd/0`. Its `ApprovedSnapshot()` check verifies
the running executable's seals.

A bundle has seven code files to protect. Our diagnostic confirmed that
`/proc/self/exe` identifies the loader in the successful layout. Checking only
that file would leave the runtime, snapshot, and libraries unchecked.
The files also need to remain accessible to host systemd after the original
AppImage mount or launcher disappears.

Copying libraries into the AppImage, setting `LD_LIBRARY_PATH`, or mounting
a user-owned directory read-only does not meet that contract. A read-only
mount does not prevent its owner from changing the source files elsewhere.
`control/executable_snapshot.cc` also rejects user-controlled loader and library
search paths.

The approved prototype uses the existing startup code:

1. Include the runtime bundle in the protected bytes handed to systemd before
   approval.
2. After approval, let the existing static starter create a private,
   root-controlled runtime directory and populate only the known bundle files.
3. Start the bundled loader with explicit paths and a clean environment.
   Preserve the service PID, pinned app lifetime, and peer identity checks.
4. Use the existing cleanup path to remove the runtime files on failure,
   cancellation, and app exit, including death while approval is pending.

The user approved this prototype on 2026-11-19. The implementation embeds all
seven files in the native starter, so its sealed executable also protects the
bundle before approval. After approval, it writes fixed filenames beneath
`/run/<service-name>/dart`. The directories have mode `0700`; the loader and
runtime have mode `0500`; the snapshot and other libraries have mode `0400`.
All belong to root.

The starter checks the app's PID and UID against the inherited process handles,
then replaces itself with the bundled loader. Dart inherits the app handle on
descriptor 0 and the launcher handle on descriptor 3. The diagnostic checks its
loaded files, performs file and socket checks, and observes both handles until
either process exits. The existing systemd cleanup service removes the session's
runtime directory.

The native staging code is in `control/prototype/bundled_dart_runtime.cc`; the
Dart diagnostic is `experiments/run_bundled_helper.dart`. Both prototype launch
paths require the disposable-VM marker. The build option
`BUILD_BUNDLED_DART_PROTOTYPE` is off by default.

Run the privileged checks in the disposable NixOS VM:

```bash
nix build .#checks.x86_64-linux.bundled-dart-bootstrap \
  --max-jobs 2 --cores 2 --print-build-logs
```

### VM results

On 2026-11-19, the check above passed with the pinned Dart 3.14.0 runtime and
Nix glibc `2.44-57`. The starter used Nixpkgs' static musl toolchain; its ELF
had no interpreter, required shared libraries, or runtime search paths.
The test's Polkit rules grant, deny, or require authentication for three
disposable users. They do not exercise a desktop password dialog.

| Check | Result |
| --- | --- |
| Approved startup | Dart runs as root with the systemd service PID; every file-backed mapping comes from its private bundle. |
| File and socket diagnostics | File read/write and socket peer PID/UID checks pass. |
| Ownership and permissions | All seven files have the expected root owner and modes; the ordinary user cannot list or overwrite them. |
| Replace the source before approval | The protected bundle still starts. |
| Denial or missing authentication agent | Dart does not start; transient units are collected. |
| App or launcher death | Dart exits and cleanup removes the runtime directory. |
| Kill Dart | Cleanup removes the runtime directory. |
| Pre-existing runtime symlink | Staging rejects it; the external sentinel survives cleanup. |
| Launcher dies while startup is queued | Dart does not start; cleanup completes. |
| Invalid compiled snapshot | The staged loader starts, Dart rejects the snapshot, and cleanup removes the directory. |

The package build also runs release-safe native staging tests for permissions,
ownership, existing paths, traversal, symlinks, and partial-write cleanup.
The existing `portable-bootstrap` VM regression passed with the shared startup
and CMake changes. The new prototype rejects execution outside the test VM;
Dart analysis, AOT compilation, formatting, ShellCheck, and Nix formatting passed.
The build result contains `bundled-dart-tests.log`.

This prototype retains native startup and cleanup. Production adoption still
needs normal AppImage acceptance, an Ubuntu VM run, and desktop password-prompt
tests. The Dart program implements runtime diagnostics and lifetime observation;
the D-Bus server and hardware operations remain migration work.

The packaging work must also record library provenance, include the required
license/source information, and track security updates. D-Bus authorization,
descriptor ownership, backend execution, and hardware behavior remain separate
migration work.

## Repeat the isolated checks

Use a new output directory for each run:

```bash
nix shell --inputs-from . nixpkgs#bubblewrap --command \
  nix develop --command \
  bash tool/test_bundled_dart_runtime.sh build/bundled-runtime-nix
```

The command should report a successful AOT launch and a failed missing-library
check. It records the other executable experiments without requiring them to
fail on future SDK versions. Results and mapped files are in `results.json`
and `aot-snapshot.json`.

To repeat with the Ubuntu libraries used above:

```bash
mkdir -p build/bundled-runtime-input
curl --fail --location \
  https://security.ubuntu.com/ubuntu/pool/main/g/glibc/libc6_2.35-0ubuntu3.18_amd64.deb \
  -o build/bundled-runtime-input/libc6.deb
echo 'cbed4dfa159019c759edae73ece1af67817e163686ad8925a26c90849ba1660a  build/bundled-runtime-input/libc6.deb' \
  | sha256sum -c
nix develop --command dpkg-deb -x build/bundled-runtime-input/libc6.deb \
  build/bundled-runtime-input/root
nix shell --inputs-from . nixpkgs#bubblewrap --command \
  nix develop --command \
  bash tool/test_bundled_dart_runtime.sh build/bundled-runtime-ubuntu \
  build/bundled-runtime-input/root/lib/x86_64-linux-gnu
```

The checksum came from Ubuntu's `jammy-security/main/binary-amd64/Packages.xz`
index on 2026-11-19. The package was chosen to match the AppImage's Ubuntu 22.04
baseline. A superseded archive may require choosing and recording a newer
package.

Both checks use the NixOS host kernel. Neither is an Ubuntu VM test or a normal
AppImage launch. The Docker daemon was unavailable during this evaluation;
the Ubuntu container build was not rerun. Bubblewrap is only the test harness
and is not a proposed runtime dependency.
