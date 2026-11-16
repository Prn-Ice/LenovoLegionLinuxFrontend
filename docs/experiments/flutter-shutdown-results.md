# Patched-engine app results — 16 November 2026

## Outcome

The isolated experiment built and tested both variants with fresh release/AOT.
It does not establish a production fix. Removing application engine retention
(B) is rejected by a first-close Ubuntu abort. Keeping retention (A) completed
the bounded local checks, but shutdown ordering remains unknown.

| Variant | Ubuntu 22.04 Debian | NixOS official appimage-run |
| --- | --- | --- |
| A: retained engine | 20/20 normal closes; installation, helper approval/denial/missing-agent, readback/restore, upgrade and purge passed | Two functional closes, ten X11 closes and ten Wayland closes passed; denial, approved retry, readback/restore and helper cleanup passed |
| B: normal reference ownership | Dashboard after 2.5s; first close aborted (`-6`); 0/1 closes passed, remaining 19 and later helper/upgrade/purge checks did not run | The same complete 22-close functional/X11/Wayland flow passed |

Both platforms proved approved-user core capture before app launch. No app
failure was rerun. The prior stock hosted core remains the baseline; no new
stock repetitions ran. No engine lifecycle tracing was added.

## Exact inputs

- App base: `77a189e1e4620d544a85509b3417fc91f3800156`
- A package source: `61367a98775765d1144f2d9bd50a1a124a1ce7df`
- B package source: `79b2923d019de10bbe665f1e52a3a720cbc2c2c3`
- Framework base: `ab2912035e160d9cad6306df307576da6128ebdb`
- Patched framework/engine source: `2ec26c4fc6b078d957242eb6c688ebc7526c7b9c`
- Actual patch order: 194525 -> 193533 -> 193126; the export manifest records
  the full patches and the test-only MockGtk conflict adaptation.
- Dart: `fa8c1270c374c1346931583a17c3b7f278d3822d`, 3.14.0; matching stable-DEPS
  Dart SDK/frontend prebuilts are recorded, not claimed as newly compiled.
- Runtime SHA256: `226a06ff64e17e4cc2468af63be9f2b737fddd680a8ae34e7e5c7c026bb506ad`
- Runtime build ID: `50fc1e9aa3a2f684cc9837bdfad045a735589fbe`

The export passed `sha256sum --check --quiet SHA256SUMS` before use. SDK, home,
and pub cache were copied privately for A and B; exported engine outputs were
mounted read-only. The lockfile was unchanged. Both packaging entry points used
the supported local-engine flags, fresh kernel/AOT, and existing package staging.
The source companions include the export manifest, source archive, provenance,
local-engine arguments and explicit experimental/non-release fields. Neither a
stock manifest nor old AOT was reused. All four shipped runtimes match the hash
above. The SDK's Git-derived prerelease-looking version is not a source roll or
runtime identity.

The original engine native result remains 83/84. The separate AT-SPI report
classifies its failure and records one unchanged test passing in a complete
environment; it does not replace that result with 84/84. See
`/tmp/opencode/flutter-shutdown-engine-experiment/atk-investigation/report.md`.

## Artifact SHA256

| Artifact | A | B |
| --- | --- | --- |
| Debian | `58cdf3943cc5b5650186cd484f7a918918f78af7781a5e2e4ba575422f5d4f43` | `3d4e8a00b03ae3c155d22b23569b5b9ef1150cdf99bb7905eeb76927e5996348` |
| Debian source | `eac236abd2fa6eaae4780a8963768218438fce6e57aed780569bbdb6fcc19c64` | `7712bca24b116ed15c8e6a1824edeb48a2788e3eaeb87ed08e4a83180b3d3960` |
| AppImage | `1e02e0f111ee7e2012c5cc67fc7eebbc2bb5df1c840a8e6945add757ffb9a910` | `0caea844a7b634d9a62ceaea4a9c747e7ee604936e72b5859305a714c99ae6f4` |
| AppImage source | `8372ba8e9390a46c82d9effc5e9543ba10c000e5c5701b731af448b6e84fc2fd` | `089b31fc36274890b06bbf3b401b0d31e597b1e55df0ec06a7a53ff61e95f3af` |
| Fresh libapp.so | `862b7e7fc729348ef8d26cb19c7bcd36fec2812a1ce097f4d8b0db681b8073ad` | `91056f001711b670e50378703978cc95714bbdb633cff91d7f253529492894f3` |

## B's first Ubuntu failure

The app logged `bad_alloc was thrown in -fno-exceptions mode`. The saved
systemd all-thread report identifies raster LWP 4237:

```text
abort
std::__fl::__libcpp_verbose_abort
std::__throw_bad_alloc
operator new
llvm::TargetPassConfig::addPass
LLVM machine-pass setup / MCJIT finalization
LLVMGetPointerToGlobal
swrast_dri.so
impeller::RenderPassGLES / ReactorGLES
Flutter Rasterizer
```

Main LWP 4213 was concurrently in `libLLVM-15.so.1` from libc `exit`. This
retains the process-exit/raster overlap seen in the stock core, but the signal
and immediate fault differ. It does not prove an OS OOM, a particular allocation
size, or that these patches caused the failure. No app/plugin frame appears in
the faulting chain. Removing the extra reference did not reliably stop raster
work before process exit.

Raw core: `/tmp/opencode/lllf-shutdown-results/B/ubuntu-core/deb-core-diagnostic/legion.core`.
Its SHA256 is `b4acf69714296bf0b78ebfcc6f93f3214bef38794d35bf04c3dc88bb213b7b81`.
The guest collector retained it and a symbolized systemd all-thread report, but
its GDB command exited nonzero before generating the separate maps/build-ID
files. Qualification status remained 1; collection status 1; archive status 0.
The retained guest GDB output is partial and must not be called complete.

An offline GDB command, with automatic host-library loading disabled, completed
and saved core mappings and raw all-thread addresses under `B/offline-core/`.
The core's own systemd report supplies matching library build IDs and the
symbolized failing chain. Attempts to fetch the exact old libc package returned
404; no mismatched newer libc was substituted for symbolization. No app reran.
Systemd report SHA256: `c038e1a7b095c95a593f47ca48b25391cdb6f8d5d2223bfc82b78cd2254d00cb`.
Offline raw-address/mappings SHA256: `515c90f29c0e7d2275cf232dcf532316592e8b90224fd355ddbb884777d9c741`.

## Environments and instrumentation

Local KVM host: AMD Ryzen 7 7840HS, Linux `7.3.1`, host QEMU `11.1.2`.
Ubuntu guest: 22.04.5, kernel `5.15.0-203-generic`, Mesa
`23.2.1-1ubuntu3.1~22.04.4`, LLVM `15.0.7-0ubuntu0.22.04.3`.
NixOS guests: kernel `6.18.60`, same guest-visible CPU; exact Nixpkgs is pinned
by the harness branch's unchanged flake.lock.

The harness is branch `experiment/shutdown-acceptance`. Ubuntu used `bc297ee`;
NixOS used `8a977b5`. PR 10's fixture/core instrumentation was reused. NixOS
adds only guest coredump/GDB tooling, core limits and accessibility service
provisioning; its standard appimage-run namespace and authorization checks stay
intact. The NixOS assertion migration was fixed before either app launched.

AT-SPI service provisioning was explicit: Ubuntu added `at-spi2-core`; NixOS
provided the same standard service through its package/D-Bus configuration.
Existing private D-Bus sessions remain in use; no critical was filtered and no
`NO_AT_BRIDGE` or module override was set. Ubuntu's inherited root
`XDG_RUNTIME_DIR` produced dconf warnings in accessibility-service subprocesses.
Those warnings remain in the logs. App close/GLib-critical gates passed for A;
this environmental imperfection was not silently repaired by rerunning it.

All Docker commands used `--init`; builds had a 45-minute outer bound and
bounded cleanup. Ubuntu VM commands had a 35-minute bound; NixOS commands had a
50-minute bound. None reached those bounds. Failed prerequisites/logs remain:
the first B build could not see external worktree Git metadata, and the first
NixOS A evaluation used the removed coredump option. Both were fixed before app
execution. They are not app retries.

## Commands, checks and limits

Per variant, the build entry was:

```bash
bash tool/build_experimental_packages.sh A_or_B deb PRIVATE_CONSUMER NEW_OUTPUT
bash tool/build_experimental_packages.sh A_or_B appimage PRIVATE_CONSUMER NEW_OUTPUT
```

The driver and package sources at the recorded commits contain the complete
Docker mounts, environment, local-engine arguments, hashes and build steps.
The acceptance entries were the standard VM runner with
`LLLF_VM_ACCELERATOR=kvm LLLF_DEB_CORE_DIAGNOSTIC_ATTEMPTS=20` and the standard
`tool/test_appimage_nixos.sh` with the derived AppImage.

Additional gates: 16 packaging tests passed, focused Dart analysis found no
issues, shell/Python/Nix syntax and ShellCheck checks passed, and the app
lockfile/launchers remained unchanged. These tool tests used a private SDK's
ordinary cached test engine; they are not patched-engine native tests.

Evidence root: `/tmp/opencode/lllf-shutdown-results/`. `results.json` records
artifact/source/AOT hashes and verified counts; `SHA256SUMS` fingerprints the
retained artifacts and logs. Successful NixOS outputs and fixture cores are
copied locally as well as retained by their result links.

No hosted run, full Flutter suite, real-hardware password cancellation, full
engine native suite, or lifecycle-order tracing ran here. A's local passes are
bounded non-reproduction, not proof of shutdown synchronization. B fails the
required matrix and is not a fix. No production fix or custom-engine adoption
is justified. Parent review is needed before a hosted A comparison or further
ordering diagnostics. PR 9, main, shared SDK, export, and published/convenience
artifacts remain unchanged.
