# Upstream tooling and Flutter review

Checked on 18 November 2026. This review compares upstream
[`9853156`](https://github.com/johnfanv2/LenovoLegionLinux/tree/98531565555d43c2e34c2c487ffcbba273c5e803)
with our `main` at `1259e87`, before the release-note changes in this PR.
Line counts include comments and blank lines. They describe reading size, not
quality, test coverage, or runtime cost. This is a source review, not an upstream
test run or a benchmark.

## Are upstream's workflows simpler?

**Their PR workflow is easier to scan, but their overall CI is not uniformly
simpler or more focused.**

| Measure | Upstream | Frontend |
| --- | --- | --- |
| PR workflow | `build_PR.yml`: 121 lines, 5 jobs | `ci.yml`: 394 lines, 10 jobs |
| All workflow YAML | 6 files, 666 lines | 3 files, 508 lines |
| Local composite actions | None | 2 files, 66 lines |

Upstream steps usually call a named script: install dependencies, build the
kernel module, test DKMS installation, or run the CLI. That makes the job's
purpose visible. Their three-distribution Docker build also shares cached
layers through Buildx.

There are trade-offs:

- `build.yml` repeats most of `build_PR.yml`. The copies already differ:
  push CI runs `test_python_unit.sh`, while PR CI runs `test_gui_startup.py`.
- `test_python_cli.sh` is a six-line startup smoke test. The GUI smoke test
  starts the app and closes it automatically. These are useful checks, but
  do not exercise our state transitions, permission failures, package upgrades,
  or helper process cleanup.
- Upstream's manual `release.yml` has no dependency on the build/test jobs. It
  bumps versions, pushes directly to `main`, builds a kernel patch, and publishes.
  Our tag workflow reuses CI and verifies that the shipped binaries, matching
  sources, and VM evidence identify the same commit.

Our extra responsibilities explain much of the size: Flutter analysis and
generation, native services, desktop integration, Nix, AppImage, Debian, and
systemd/Polkit VM checks. They do not excuse inline JSON construction or repeated
setup. Good improvements would make each job easier to read while retaining its
acceptance checks. Splitting YAML alone would mostly move the complexity.

Sources: upstream [PR CI](https://github.com/johnfanv2/LenovoLegionLinux/blob/98531565555d43c2e34c2c487ffcbba273c5e803/.github/workflows/build_PR.yml),
[push CI](https://github.com/johnfanv2/LenovoLegionLinux/blob/98531565555d43c2e34c2c487ffcbba273c5e803/.github/workflows/build.yml),
[release workflow](https://github.com/johnfanv2/LenovoLegionLinux/blob/98531565555d43c2e34c2c487ffcbba273c5e803/.github/workflows/release.yml),
and our [CI guide](ci.md).

## Is the Python simpler than our native and shell code?

**Several small Python methods are clearer; the whole design is not clearly
simpler.** Our native services are C++, rather than C scripts.

Upstream's `BoolFileFeature`, `BatteryConservation`, and CLI feature methods
express reads and writes directly. File access, parsing, and subprocess results
benefit from Python's standard library. We can get the same advantages from
Dart's `File`, `Process`, and JSON APIs.

The larger files complicate the picture: `legion.py` has 2,351 lines,
`legion_cli.py` 609, and `legion_gui.py` 2,030. The implementation includes a
global feature registry, string-based dispatch, inheritance, and repeated CLI
wrappers. For example, `write_file_with_legion_cli` calls `pkexec legion_cli`
and waits with `communicate(timeout=None)`. It does not perform the process
containment and executable-snapshot work in our native helper.

Our `control/control_commands.cc` is only 184 lines and has a direct allow-list,
but names such as `f`, `v`, and `e` make it harder to read than it needs to be.
Use `feature`, `value`, and `error` when revising that code. Preserve validation,
Polkit, and process lifetime rules when simplifying the helper.

Shell remains concise for command orchestration: `portable_distro_evidence.sh`
is 17 lines and retrieves logs and evidence while preserving failure status.
The manifest-building tail of `test_portable_distro.sh` is a better Dart
candidate: it builds structured data through nested shell and jq quoting.
QEMU/SSH invocation and boot/recovery scripts have a stronger reason to remain
shell, especially when they must run without an installed Dart SDK.

Sources: upstream [hardware model](https://github.com/johnfanv2/LenovoLegionLinux/blob/98531565555d43c2e34c2c487ffcbba273c5e803/python/legion_linux/legion_linux/legion.py)
and [CLI](https://github.com/johnfanv2/LenovoLegionLinux/blob/98531565555d43c2e34c2c487ffcbba273c5e803/python/legion_linux/legion_linux/legion_cli.py).
Scoped simplifications are recorded in `lllf-b68.2` for discussion before migration.

## Release notes

Upstream's [v0.1.8 notes](https://github.com/johnfanv2/LenovoLegionLinux/releases/tag/v0.1.8)
use feature/fix headings, commit and PR links, contributor credit, and a full
changelog link. Those headings help readers find changes quickly.

Our published alpha.2 notes were already shorter than upstream's. The long
qualification report was in the unpublished alpha.1 draft. The useful change is
clearer grouping and descriptions, rather than merely fewer words.

The release generator now groups conventional subjects, omits empty sections,
and links commits and the full changelog. It preserves legacy subjects under
Maintenance and puts breaking changes first. Contributor summaries and automatic
version bumps are outside this change. Existing published releases are preserved.

Two concrete copy findings:

- Our alpha.2 entry `ci: require PR checks without duplicate merge runs` exposes
  the raw commit prefix among unprefixed entries. The generator now renders the
  description under Maintenance, giving entries a consistent form.
- Upstream v0.1.7 says `1 commits` and `1 contributors`. Its template should
  render `1 commit` and `1 contributor`. This is third-party generated text;
  we have not changed it.
- Upstream `legion.py:302` logs `does not exist. exits: %d`. The repeated check
  and typo obscure the useful fact. `Feature %s has no matching file for %s`
  would identify the feature and its search pattern. This remains upstream-owned.

See [release-note conventions](releases.md#release-notes) and
[commit enforcement](ci.md#merge-requirements).

## Flutter and Dart versions

| Channel | Verified version or revision | Dart |
| --- | --- | --- |
| Stable | Flutter 3.50.0, released 11 November | 3.14.0 |
| Beta | Flutter 3.51.0-0.1.pre, released 11 November | 3.15.0-118.1.beta |
| Master | `23946edee2790d5ae10dc5720fe3daf81c605b0b`, 17 November | SDK revision identifies 3.15.0-154.0.dev |

Our project and CI already pin the latest stable SDK. The inherited shell's
`flutter` was still 3.47.9; `nix develop --command flutter --version` correctly
reported the project's 3.50.0. Use the project environment for comparisons.

Version sources: [official Linux release manifest](https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json),
[master snapshot](https://github.com/flutter/flutter/commit/23946edee2790d5ae10dc5720fe3daf81c605b0b),
and its [Dart version file](https://github.com/dart-lang/sdk/blob/26e38955d9d4a60612d9217e2feec1817a1fd550/tools/VERSION).

### Native interop and scripting

- Flutter 3.50 declares Objective-C FFIgen and Java/Kotlin JNIgen stable.
  These join existing C support; most of the newly stable functionality serves
  Apple and Android integrations, rather than replacing Linux C++ services.
- Dart build hooks build and bundle native libraries during the normal Dart or
  Flutter build. `ffigen` generates C bindings, and `@Native` resolves code assets.
  This can reduce native build plumbing for a small in-process library.
- FFIgen still cannot bind C++ classes or templates directly. A C-compatible
  interface is required. FFI also does not provide administrator authorization
  or process isolation; our privileged service should remain behind D-Bus.
- More host tooling can use Dart now, without an SDK upgrade or FFI. Packaging
  manifests, archive inventories, release generation, and validation already do.
  This PR adds a small Dart commit checker. Prefer `Process` argument lists to
  constructing shell command strings.
- Dart 3.14 adds `dart run -e` for inline snippets and improves executable caching
  for package commands. Reviewed 3.15 changes include `dart build cli --define`;
  they do not establish a new Linux C++ interop model. Keep maintained tooling
  in named files so it remains easy to read and test.

Sources: [Flutter 3.50 announcement](https://flutter.dev/blog/whats-new-in-flutter-3-50),
[FFIgen limitations](https://docs.flutter.dev/interop/ffigen),
[Dart hooks](https://dart.dev/tools/hooks),
and [SDK changelog](https://github.com/dart-lang/sdk/blob/main/CHANGELOG.md).
The moving SDK changelog still labels 3.14 unreleased; the official release
manifest establishes the shipped version.

### Linux window styling and shutdown

Flutter 3.50 includes experimental `WindowControllerLinux` APIs for decoration,
app-painted backgrounds, transparency, native move/resize gestures, and native
window handles. Source in stable, beta, and master still marks these APIs
experimental. They could eventually reduce runner code, but are not a verified
replacement for our Yaru/libhandy integration or a fix for Wayland corner clipping.

There is one relevant beta change: the task-runner fix
[#194525](https://github.com/flutter/flutter/pull/194525) is merged and present in
beta and master. Stable retains the older timeout-source implementation.
The separate renderer-lifetime work
[#193533](https://github.com/flutter/flutter/pull/193533) remains open. Source
inclusion alone does not prove our close crash is fixed.

Package checks found:

- `handy_window` is still 0.4.2; its Flutter-painted rounding
  [PR 61](https://github.com/ubuntu/handy_window.dart/pull/61) remains open.
- Yaru is 12.0.0 and `yaru_window` is 0.2.2, matching our resolved releases.
- `window_manager` 0.7.0 is released. Its 0.6 migration replaces platform plugins
  with `nativeapi`; 0.7 requires Flutter 3.50/Dart 3.14 and `material_ui`.
  It adds a richer window API, but our 0.5.2 copy comes through
  `yaru_window_manager ^0.1.3`, whose `^0.5.1` constraint excludes the new series.
  That Yaru implementation serves Windows/macOS, not our Linux window path.
  A migration therefore needs an explicit design decision and platform checks.

Keep stable for production. A disposable beta shutdown comparison and a separate
window-tooling evaluation are recorded in `lllf-b68.1`. Neither beta/master nor
the new window backend was built or visually tested in this review.

Sources: [stable Linux window APIs](https://github.com/flutter/flutter/blob/3.50.0/packages/flutter/lib/src/widgets/_window_linux.dart),
[beta task runner](https://github.com/flutter/flutter/blob/3.51.0-0.1.pre/engine/src/flutter/shell/platform/linux/fl_task_runner.cc),
[window_manager changelog](https://pub.dev/packages/window_manager/changelog),
and our [window-corner evidence](dependencies.md#linux-window-corners).
