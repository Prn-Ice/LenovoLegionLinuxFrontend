# Isolated Flutter shutdown experiment

Preparation for `lllf-dt0.5.16.1`; no engine build or app test has run here.
Custom-engine testing is approved, not adoption, merging, tagging, or release.
PR 9, its `77a189e` source, and the shared SDK remain unchanged.

## Variants and isolation

Both branches start at `77a189e1e4620d544a85509b3417fc91f3800156`.

| Variant | Worktree | Branch | App change |
| --- | --- | --- | --- |
| A | `/tmp/opencode/lllf-shutdown-app-a` | `experiment/shutdown-app-a` | None; retain `MyApplication::engine`. |
| B | `/tmp/opencode/lllf-shutdown-app-b` | `experiment/shutdown-app-b` | Remove the extra engine reference, its assignment, and its release. |

B changes only four lines in `linux/runner/my_application.cc`: delete the
retention comment and `FlEngine* engine` field, the `g_set_object` after
`fl_view_new`, and the `g_clear_object` in application disposal. The view,
plugins, application hooks, `main.cc`, and launchers remain unchanged. Do not
add forced main-window destruction, `g_object_run_dispose`, `_Exit`, private
engine methods, renderer flags, or a substitute launch flow.

Test both variants independently with the same delivered engine. A is the
compatibility/control variant; B is an ownership experiment enabled by task-runner
fix 194525, not an adopted fix. A failure does not prohibit B's separate test.
This supersedes the conditional B trial in the earlier patch audit.

The engine builder owns its checkout. Do not inspect that checkout or poll its
build. The parent will forward the completed handoff before app builds start.

## Existing stock baseline

Use run `43735297027` and artifact `14170452029`; do not repeat 65 stock closes.
The exact stock package `3b169c4d1fe8cb684c958363ded0a43b399b1dfed226e390ef023af06a85bae2`
rendered Dashboard, then close 1/20 exited `-11` on KVM/AMD EPYC 9V45. The
approved-user abort first proved unlimited core limits and GDB capture. The app
core shows LLVM/MCJIT work through Mesa on `io.flutter.rast` while the main
thread is in libc `exit`. It establishes overlapping lifetimes, not the exact
causal defect or the same instruction as the older Mesa readback crash.

Retained proof: `/tmp/opencode/pr10-hosted-core-diagnostic-summary.md` and
`/tmp/opencode/pr10-run-43735297027-evidence/deb-core-diagnostic/`.

## Engine handoff required before building

Require the following from the parent; do not infer paths or output names:

- Full patched framework and engine source revisions, Dart revision, DEPS
  resolution, actual patch application order, patch hashes, and conflict edits.
  The audit pins 193533 -> 193126 -> 194525; record any equivalent dependency
  ordering used by the builder rather than relabeling it.
- A private, compatible Flutter SDK and a completed local-engine `src` tree or
  export with the required `out` layout. Keep all writable caches private; do
  not run app commands against the builder's active checkout or shared SDK.
- Actual target and host output names, architecture, runtime mode, GN args,
  compiler/sysroot and libc requirements, engine build log, and test results.
- Runtime `libflutter_linux_gtk.so`, matching public headers and `icudtl.dat`,
  matching `gen_snapshot`, Dart SDK/frontend-server snapshot, patched platform
  dill/libraries, generated `sky_engine`, and any tool-requested shader/font
  utilities. Confirm provenance for any fallback to cached host tools.
- SHA256 and build ID for runtime and symbols; retain unstripped/debug symbols
  and the matching source archive. Record whether tracing/assertions or
  unoptimized code are enabled.

A release/AOT candidate is needed for matched package evidence. A debug/JIT
engine may support a labeled initial probe, but cannot be paired with stock
`libapp.so` or called a release-equivalent test. Stop at missing or incompatible
inputs; do not silently download a different engine or upgrade the framework.

## First bundle probe, after the handoff

Set these variables from the delivered manifest, not guessed locations:
`SDK`, `ENGINE_SRC`, `LOCAL_ENGINE`, and `LOCAL_ENGINE_HOST`. Run from each
variant's worktree in an isolated build environment. Confirm the SDK's verbose
help against the delivered tool version before invoking:

```bash
export PATH="$SDK/bin:$PATH"
flutter --version --machine
flutter --local-engine-src-path="$ENGINE_SRC" \
  --local-engine="$LOCAL_ENGINE" --local-engine-host="$LOCAL_ENGINE_HOST" \
  pub get --enforce-lockfile
flutter --local-engine-src-path="$ENGINE_SRC" \
  --local-engine="$LOCAL_ENGINE" --local-engine-host="$LOCAL_ENGINE_HOST" \
  build linux --release --no-pub --verbose \
  --dart-define=LLLF_ENABLE_PORTABLE_CONTROL=true
cmake -S linux -B build/linux/x64/release -DBUILD_PORTABLE_CONTROL_HELPER=ON
flutter --local-engine-src-path="$ENGINE_SRC" \
  --local-engine="$LOCAL_ENGINE" --local-engine-host="$LOCAL_ENGINE_HOST" \
  build linux --release --no-pub --verbose \
  --dart-define=LLLF_ENABLE_PORTABLE_CONTROL=true
```

Expect the log and generated CMake inputs to select the delivered local engine
and `gen_snapshot`, not stock cached artifacts. Verify the bundled runtime's
hash/build ID and record freshly generated `libapp.so` and asset hashes. Keep
separate build/cache/output directories for A and B. Run the bundle executable
through ordinary desktop launch and close once; this is a smoke probe, not
package acceptance. A failure ends that variant's probe and requires a core.

## Minimal experimental packaging changes, not implemented yet

Reuse the pinned Ubuntu 22.04 builder and existing package layouts. Verify the
engine's ELF interpreter, GLIBC/GLIBCXX requirements, DT_NEEDED, and RPATH there
before packaging. An engine needing newer libc cannot qualify Jammy; record
the mismatch rather than bundle libc or add a runtime workaround.

The narrow build-only changes needed once the handoff is known are:

1. `tool/package_release.dart`: pass the same explicit local-engine arguments to
   both `_runBuild` invocations and dependency resolution. Record local-engine
   provenance in captured inputs and generate an experimental rebuild recipe
   containing those arguments. Preserve the clean-tree, lockfile, bundle, and
   source-pairing checks. Commit the adapter before building.
2. `tool/build_deb.sh` and `tool/build_appimage.sh`: use a verified private SDK
   export plus the delivered engine layout in the existing Ubuntu builder.
   Record their hashes instead of claiming the stock SDK archive checksum.
   These are experiment-branch adaptations, not edits to production build pins.
3. Package fresh variant-specific bundles with the existing Debian/AppImage
   staging, ELF checks, helper build, notices, and source archiver. Preserve
   `packaging/debian/legion_frontend`, `packaging/appimage/AppRun`, desktop files,
   package ID, installed-service default, and helper authorization boundaries.
4. Generate the normal package/source inventories and SHA256SUMS from those
   exact bytes. Add `experimental: true`, `release_qualification: false`, variant,
   app commit, patched SDK/source revisions, runtime/symbol/gen_snapshot hashes,
   GN/build options, patch list, and adapter/harness commit or patch hashes.
   Include this provenance and the patch/source handoff in the source companion.
   Stock `flutter --version` output alone is not patched-engine provenance.

Do not swap a library into an old package or reuse its source manifest. Give
each output directory a variant/engine identity; no convenience-image update.
Existing AppImage runtime inputs remain pinned: type-2 runtime, its source and
license archives, distro-library sources, fonts/schemas/icons, static helper and
cleanup ELF. Reuse `tool/fetch_appimage_runtime.py` and
`tool/bundle_appimage_runtime.py`; do not omit these assets for a smaller test.
The Debian output must also include its newly hashed `vm-fixtures.tar.gz`.

## Matched acceptance contract

Use fresh VMs and identical harness/engine settings for A and B. Freeze count
limits before starting; every close is a required pass, never a retry to green.
Stop a variant's platform flow on its first failure and preserve skipped steps.
Then test the other variant independently. Do not rerun an app failure.

| Flow, per variant | Standard entry | Required behavior |
| --- | --- | --- |
| Ubuntu 22.04 Debian | `bash tool/test_portable_distro.sh IMAGE SHA256 OUTPUT --deb RELEASE` | Install/verify payload; 20 Dashboard/normal-close checks using PR 10's opt-in diagnostic overlay; unchanged helper approval/denial/missing-agent, write/readback/restore, upgrade, purge, and persistent-file checks. |
| NixOS AppImage | `bash tool/test_appimage_nixos.sh APPIMAGE OUTPUT` | Official `appimage-run`; existing Settings close and authorization/readback/restore close; ten required X11 closes, then ten native Wayland closes. |

NixOS's full flow has up to 22 app closes: two functional closes and 20 repeated
closes. Do not relabel 22 as 20 or remove functional checks to meet a count.
If it fails on its first Settings close, later authorization/Wayland checks are
unverified, not waived. A separate Wayland-only test would need explicit scope
and results, not a hidden continuation after failure.

Use PR 10 commit `bede43f42d5df3516a0e76ee5c2abbbff95fc97f`'s changes only for
`deb_test.py`, `qualify_deb.sh`, `deb_core_diagnostic.sh`, and
`test_portable_distro.sh`. No workflow is needed. Set
`LLLF_DEB_CORE_DIAGNOSTIC_ATTEMPTS=20`. Keep hash, first-frame, normal-close,
exit-zero and GLib/GObject-critical gates intact. The overlay is separately
identified test instrumentation; it is not the package's app source.

For both flows record actual CPU/kernel/QEMU, VM image/Nixpkgs lock, rendering
library versions and build IDs. CPU vendor is an observation, not a gate.
Run locally first; request hosted work only if local results need the original
reproduction environment. No new workflow or infrastructure is authorized here.

## Guest-only failure capture

Retain PR 10's standard `systemd-coredump`/`coredumpctl`/GDB approach on Ubuntu.
Prove unlimited approved-user soft/hard core limits with one harmless abort,
retained raw core, and backtrace before app launch. Bound each process core to
2 GiB and collection time to six minutes; record collection/archive statuses
separately so they cannot replace the app's failure.

Before running NixOS, add only equivalent guest test instrumentation to the
existing VM module: core limits, bounded external systemd storage, GDB/binutils,
the same abort proof, and failure collection in `try`/`except`/`finally` that
re-raises the original test failure. This overlay is not yet implemented or
verified. Do not weaken the official `appimage-run` namespace/trust behavior.

NixOS cores require special care: the executable is under `appimage-run`'s
cache/mount path, not `/usr/lib/legion_frontend`. Match the recorded app PID or
`COREDUMP_COMM=legion_frontend`/UID; retain `coredumpctl info`, maps, AppDir
binaries and symbols before guest shutdown. Point offline GDB at the matching
AppDir/sysroot, not host libraries. Do not change the launcher just to make
core paths easier. Do not report a missing/truncated core as successful capture.

Retain raw core, all-thread `bt full`, thread IDs, mappings, build IDs, signal,
app/engine hashes, fixture proof, per-attempt status/logs/screenshots, and source
pairing in `/tmp/opencode/lllf-shutdown-results/{A,B}/`. Use new paths; never
erase earlier output. Capture failure before disposing the VM. Core collection
does not authorize continuing close attempts.

## Ordering probe and interpretation

Optional tracing is a separate diagnostic run, not normal acceptance. After
the parent approves its concrete instrumentation, log engine Shutdown entry
and return, engine/renderer dispose/finalize, main-loop return, and process exit
with thread IDs and monotonic timestamps. Use matching symbols or a separately
identified tracing build; do not call lifecycle methods from the tracer.
Its engine/runtime and app hashes must be separate from uninstrumented results.

- A failure plus B success suggests reference ownership matters; it does not
  prove these patches fix process-exit synchronization.
- Two clean matrices mean bounded non-reproduction on these environments, not
  proof of engine finalization or a qualified production release.
- A core with main-thread `exit` overlapping raster work preserves the known
  lifecycle class. A new abort/UAF/plugin stack must be classified separately.
- No Shutdown/finalize trace means ordering is unknown. A Shutdown entry without
  its completion before main-loop/process exit is not proof of clean teardown.

## Sources and preparation status

Context7 supplied only generic/older Flutter guidance. Verified local-engine
flags and the runtime-mode constraint against Flutter's current
[tool documentation](https://github.com/flutter/flutter/blob/main/docs/tool/README.md#using-a-locally-built-engine-with-the-flutter-tool)
and the same document at framework `ab2912035e160d9cad6306df307576da6128ebdb`.
The pinned tool's `local_engine.dart` and `artifacts.dart` show which target and
host artifacts it resolves, including `gen_snapshot`, patched platform data,
headers, and Dart SDK. Do not apply the upstream contribution guide's general
advice to rebase to main; this experiment is pinned to its audited sources.

Prepared: app worktrees, four-line B deletion, and this contract. Checked:
exact source diff and `git diff --check`. Not run: engine/app builds, resolver,
unit tests, bundle probes, package construction, VM acceptance, or tracing.
Packaging adapters and the NixOS capture overlay await the engine handoff and
are not implemented. No claim of patched-engine compatibility is made.

The archived preparation files are under
`/tmp/opencode/lllf-shutdown-app-preparation/`: `variant-b.diff` contains only
the four runner deletions; `deb-core-diagnostic-overlay.diff` contains PR 10's
four test-file changes without its workflow. Apply the latter to a separate
harness worktree based on either app branch, not to the source being packaged.
Verify each patch with `git apply --check` before use and record its SHA256.
