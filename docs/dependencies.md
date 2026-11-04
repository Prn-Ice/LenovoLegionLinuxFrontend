# Stable dependencies

Use stable packages that work together, not the largest version numbers at any
cost. The application keeps its resolved graph in `pubspec.lock`; do not add
dependency overrides to force incompatible versions.

## Flutter and development environments

Use Flutter **3.47.9** or newer on the stable channel; CI pins 3.47.9, whose
bundled Dart is 3.13.7. Install the Linux desktop compiler, CMake, Ninja,
pkg-config, GTK development headers, and native development libraries required
by Flutter. Native service builds additionally need GLib/GIO, and control-service
builds need Polkit development files. Package names depend on the distribution.

Nix and direnv are optional. `.envrc` only activates a development shell when
`LLLF_DEV_FLAKE` is set to a flake reference by the contributor. There is no
project flake or required shared SDK, and the repository does not update or
install a system-wide SDK for you.

Nixpkgs previously packaged Flutter 3.47.4. A custom flake may package
3.47.9 using Nixpkgs' Flutter builder, patches, and wrapper, with pinned source,
Dart, and engine artifact hashes. Remove that custom pin once Nixpkgs packages
3.47.9 or newer. Its verified target is x86_64-linux; do not assume a successful
Linux build proves Android, another host architecture, or macOS support.

Update your own flake and lockfile deliberately, if you maintain one:

```bash
nix flake update
direnv reload
direnv exec . flutter --version
```

Check the custom pin before updating: it intentionally rejects a changed upstream
Flutter baseline so tool dependencies and patches cannot drift silently. Do not
run `flutter upgrade` against the read-only Nix SDK.

## Retained compatibility boundaries

### Equatable 2.1

Equatable 3 removes runtime-type checks from equality. Events such as
`AboutStarted` and `AboutRefreshRequested` have identical empty property lists
but represent different commands. Keep `equatable: ^2.1.0` until a separately
reviewed equality migration preserves those distinctions, including set/hash
behavior. `test/core/event_equality_test.dart` guards the application contract.

### Hive generation and the Flutter test graph

Flutter 3.47.9's `flutter_test` pins `test_api` to 0.7.12 and `matcher` to 0.12.20.
`bloc_test` brings in `test`; the compatible `test` 1.31.1 and `test_core` 0.6.18
require analyzer below 14. Newer test releases require a different `test_api`.

The newest `hive_ce_generator` 1.12.1 and `build_runner` 2.17.1 require analyzer
14. They cannot share this application's test graph. A disposable Pub resolution
with those versions reproduces the conflict; overriding analyzer or SDK test
pins is not a fix.

Keep the latest mutually compatible releases:

| Package | Resolved version |
| --- | --- |
| `hive_ce_generator` | 1.11.2 |
| `build_runner` | 2.15.1 |
| `analyzer` | 12.1.0 |

Recheck when Flutter's test pins and a released generator/build graph accept the
same newer analyzer. Leave transitive build/formatter packages to Pub rather
than pinning or overriding them individually.

Rechecked on 2026-11-04: the installed SDK and latest generator/build releases
still have this boundary. Pub metadata reports `test` 1.33.0 supports analyzer
14, but requires `test_api` 0.7.15 rather than Flutter's pinned 0.7.12. Keep the
compatible graph above until the SDK test pins align (tracked in `lllf-db5`).

The app retains its Dart 3.11 **source language** floor so generators can parse
its source. This does not select an old runtime: the Flutter 3.47.9 minimum requires
Dart 3.13, and the environment supplies 3.13.7. Raise the source language and apply
newer syntax fixes together with a compatible generator analyzer, followed by
real regeneration. Do not suppress diagnostics or edit generated code to hide
parser incompatibilities.

Other transitive packages remain below their latest releases because their
parents or Flutter constrain them, including Yaru's layout/window dependencies,
file picker's `cross_file`, and Flutter's `material_color_utilities`. Recheck
`flutter pub outdated --transitive` after each upgrade; do not promote transitives
to direct dependencies merely to make the output look current.

## Repeatable upgrade checks

Read current release notes and use Context7 for version-sensitive APIs. Inspect
the exact resolved implementation when documentation is stale. Probe major
version conflicts in a disposable directory before editing the working graph.
Update the manifest and lock together, preserving unrelated work.

Run these in the Flutter environment used for the change:

```bash
flutter pub upgrade
flutter pub outdated --transitive
flutter pub get --enforce-lockfile
dart run build_runner build
git diff --exit-code -- 'lib/**/*.g.dart'
flutter analyze
flutter test
flutter build linux --release
```

Review major-version changes explicitly before changing manifest constraints.
`flutter pub upgrade --major-versions` is a useful probe, not permission to change
equality, storage formats, or provider lifetime silently. The full test suite
includes `test/core/riverbloc_contract_test.dart`, which exercises production
provider initialization, repository replacement, state delivery, and disposal.

A passing resolver, test suite, or release build does not prove real Polkit/D-Bus
authorization, device writes, file-picker portals, or visual behavior. Record
those checks separately and state which were not performed.

## Primary sources

- [Flutter stable release manifest](https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json)
- [Flutter SDK test pins](https://github.com/flutter/flutter/blob/3.47.9/packages/flutter_test/pubspec.yaml)
- [Flutter SDK tool changes](https://github.com/flutter/flutter/compare/3.47.4...3.47.9)
- [Equatable breaking changes](https://pub.dev/packages/equatable/changelog)
- [Hive generator metadata](https://pub.dev/api/packages/hive_ce_generator)
- [Build runner metadata](https://pub.dev/api/packages/build_runner)
- [Yaru release notes](https://pub.dev/packages/yaru/changelog)
