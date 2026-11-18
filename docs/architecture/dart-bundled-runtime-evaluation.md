# Bundling the Dart helper's runtime

The isolated startup check passed with copied Ubuntu 22.04 and Nix glibc
libraries. This supports bundling as the next option to develop. It does not
yet establish privileged startup through the normal AppImage launch.

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

## What privileged startup still needs

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

The smallest candidate using our existing startup code is:

1. Include the runtime bundle in the protected bytes handed to systemd before
   approval.
2. After approval, let the existing static starter create a private,
   root-controlled runtime directory and populate only the known bundle files.
3. Start the bundled loader with explicit paths and a clean environment.
   Preserve the service PID, pinned app lifetime, and peer identity checks.
4. Extend the existing cleanup path to remove the runtime files on failure,
   cancellation, and app exit, including death while approval is pending.

This would retain and extend native startup and cleanup code. It is a design
candidate, not an approved or implemented bridge. It adds protected file
staging and cleanup, although it avoids maintaining a custom Dart runtime.
Before implementation, agree on that scope and demonstrate it in the disposable
systemd/Polkit VMs. A replacement implemented entirely in Dart would still need
a way to start its runtime safely before that runtime can manage these files.

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
