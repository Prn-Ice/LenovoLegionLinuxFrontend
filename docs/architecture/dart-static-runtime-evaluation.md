# Dart 3.14.0 static-runtime evaluation

## Recommendation

We found no documented way to build a fully static Linux runtime from the
unmodified Dart 3.14.0 SDK. We reviewed the source but did not attempt a static
build. Prefer the [bundled runtime](dart-bundled-runtime-evaluation.md), which
passed isolated startup checks, while its privileged startup design is reviewed.

A custom static build may be possible through GN configuration or a source
fork. Its maintenance cost and runtime compatibility remain unverified.

## Evidence

The 3.14.0 runtime build files distinguish a static **Dart component** from an
executable:

- [`runtime/runtime_args.gni`](https://github.com/dart-lang/sdk/blob/3.14.0/runtime/runtime_args.gni)
  declares `dart_component_kind = "static_library"` and describes it as
  controlling whether the VM is built as a static or shared library. It has no
  `static_executable`, libc, or linker-mode argument.
- [`runtime/bin/BUILD.gn`](https://github.com/dart-lang/sdk/blob/3.14.0/runtime/bin/BUILD.gn)
  builds `dart`, `dartaotruntime`, and `dartcliruntime` with GN's ordinary
  `executable()` target. The executable template itself adds no static-link
  flags. It does, however, inherit the common Linux configs described below.
- The same file's `dart_embedder_runtime_jit` target sets
  `complete_static_lib = true`, but that target is a static archive for an
  embedder, not a runnable Linux ELF. This is the relevant distinction between
  a static C++ library and a fully static helper.

The inherited upstream configs clarify the scope of that observation:

- [`build/config/linux/BUILD.gn`](https://github.com/dart-lang/sdk/blob/3.14.0/build/config/linux/BUILD.gn)
  explicitly uses `-static-libgcc` and `-static-libstdc++`, which statically
  link those compiler libraries. Its executable config otherwise selects PIE
  (`-pie`); it does not select `-static`.
- [`build/config/compiler/BUILD.gn`](https://github.com/dart-lang/sdk/blob/3.14.0/build/config/compiler/BUILD.gn)
  supplies ordinary Linux hardening and optimization flags and declares
  `runtime_library` with `dl` and `pthread`. No fully static Linux executable
  option appears in the inspected compiler configs.
- [`build/toolchain/linux/BUILD.gn`](https://github.com/dart-lang/sdk/blob/3.14.0/build/toolchain/linux/BUILD.gn)
  selects GCC or Clang compiler-driver link commands. It exposes toolchain
  prefixes, not a static-link mode.
- [`tools/gn.py`](https://github.com/dart-lang/sdk/blob/3.14.0/tools/gn.py)
  forwards user-supplied `--gn-args`, toolchain prefixes, and sysroots. It
  does not define a static-link switch. GN itself permits additional
  configuration, so this inspection does not rule out supplying custom
  `ldflags` through GN or a source change.

The standard compiler has no static-link option. Context7's current official
[`dart compile exe` documentation](https://github.com/dart-lang/site-www/blob/main/src/content/tools/dart-compile.md)
describes a standalone native executable containing Dart code, dependencies,
and a small Dart runtime; its options include target OS and architecture, but
not libc or static linking. The pinned command confirms the same:

```text
dart compile exe --help
  --target-os [android, fuchsia, ios, linux, macos, windows]
  --target-arch [arm, arm64, arm64e, ia32, riscv32, riscv64, x64]
```

The runtime also has a direct dynamic-loader dependency:

- [`runtime/bin/BUILD.gn`](https://github.com/dart-lang/sdk/blob/3.14.0/runtime/bin/BUILD.gn)
  links `dl` on non-Windows platforms.
- [`runtime/lib/ffi_dynamic_library.cc`](https://github.com/dart-lang/sdk/blob/3.14.0/runtime/lib/ffi_dynamic_library.cc)
  uses `RTLD_DEFAULT` for `DynamicLibrary.process()` and `dlopen`-based
  loading for ordinary libraries. A static executable would need explicit
  proof that the chosen libc's loader, exported process symbols, and every
  native asset path still work. The source does not provide that proof.

The upstream issue history points to libc-specific runtimes rather than a
documented static Linux runtime:

- [#55782, “Building app for Linux musl?”](https://github.com/dart-lang/sdk/issues/55782)
  says the supported practical answer is an SDK built for Alpine/musl. It
  does not describe a static build.
- [#61374, “Add an option to specify `dartaotruntime`”](https://github.com/dart-lang/sdk/issues/61374)
  records that AOT snapshots can be exchanged between glibc and musl for the
  same architecture, while `dartaotruntime` remains libc-specific. It also
  notes that the SDK currently selects the runtime by platform and does not
  offer the requested runtime override.
- [#38166, “Add possibility to build dart sdk with static linking for linux”](https://github.com/dart-lang/sdk/issues/38166)
  remains an open feature request, with no upstream static-linking contract.

## What remains unverified

The [existing executable checks](dart-helper-build-checks.md) show the normal
dynamic runtime's dependencies. The bundled-runtime experiment also checks
process-symbol lookup. Neither establishes that those symbols would be
available from a fully static executable.

There is a separate launcher constraint for `dart compile exe`: the 3.14.0
[`runtime/bin/main_impl.cc`](https://github.com/dart-lang/sdk/blob/3.14.0/runtime/bin/main_impl.cc)
calls `Platform::ResolveExecutablePathInto()` and then
`Snapshot::TryReadAppendedAppSnapshot(executable_path)`. Linux implements the
former through `/proc/self/exe`. Invoking the ELF through `ld-linux` therefore
can make the loader, rather than the Dart executable, appear as `/proc/self/exe`
and hides the appended snapshot. This is the documented failure mode in
[upstream issue #50926](https://github.com/dart-lang/sdk/issues/50926). It is
independent of whether the runtime's ELF dependencies are bundled or static.

The review stopped before downloading and building the full SDK because it
found no documented fully static configuration to reproduce. This is not a
failed static build or proof that source patches are necessary.

Further static-runtime work would need to choose and test a custom
GN/toolchain configuration, then check FFI, process-symbol exports, snapshot
loading, and any required native assets. We would maintain that build alongside
Dart upgrades and the selected libc's security updates. The normal AppImage
approval, denial, process-lifetime, and cleanup tests would still be required.
