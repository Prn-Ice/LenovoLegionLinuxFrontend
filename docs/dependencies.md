# Dependencies

Use compatible stable packages and commit `pubspec.lock`.

## Flutter and build tools

- Flutter stable **3.47.9** or newer; CI pins 3.47.9 with Dart 3.13.7
- A Linux desktop compiler, CMake, Ninja, and pkg-config
- GTK development headers and Flutter's native development libraries
- GLib/GIO development files for native services
- Polkit development files for control-service builds

See [contributor setup](../CONTRIBUTING.md) for installation commands and optional
Nix/direnv configuration.

The native Linux app journeys use Flutter's SDK-provided `integration_test` as a
development dependency. It follows the installed Flutter version; no external
desktop automation tool or production test-mode flag is needed. See
[the integration journey command](../CONTRIBUTING.md#linux-app-integration-journey).

## Why some packages are held back

### AppImage runtime

AppImage qualification pins the versioned type-2 runtime `20251108`, its binary
checksum, source archives, and notices in `packaging/appimage/build-inputs.json`.
The upstream `continuous` build changes in place. Recheck versioned releases when
upgrading the runtime. See [the AppImage build](appimage.md) for the host library
baseline and remaining runtime package-provenance checks.

### Equatable 2.1

Equatable 3 removes runtime-type checks from equality. Events such as
`AboutStarted` and `AboutRefreshRequested` have identical empty property lists
but represent different commands. Keep `equatable: ^2.1.0` until an upgrade
preserves event equality and hashing. `test/core/event_equality_test.dart` checks
this behavior.

### Hive code generation and test dependencies

Flutter 3.47.9's `flutter_test` pins `test_api` to 0.7.12 and `matcher` to 0.12.20.
`bloc_test` brings in `test`; the compatible `test` 1.31.1 and `test_core` 0.6.18
require analyzer below 14. Newer test releases require a different `test_api`.

The newest `hive_ce_generator` 1.12.1 and `build_runner` 2.17.1 require analyzer
14. These versions conflict with Flutter's test dependencies. Do not override
analyzer or Flutter's pinned test packages.

Keep the latest mutually compatible releases:

| Package | Resolved version |
| --- | --- |
| `hive_ce_generator` | 1.11.2 |
| `build_runner` | 2.15.1 |
| `analyzer` | 12.1.0 |

Recheck when Flutter's test packages and the code generators support the same
analyzer version. Let Pub choose indirect build and formatter dependencies.

Checked on 2026-11-04: the conflict remains. Pub metadata reports `test` 1.33.0
supports analyzer 14, but requires `test_api` 0.7.15 rather than Flutter's pinned
0.7.12. Keep the versions above until Flutter supports the required test packages
(tracked in `lllf-db5`).

The app uses Dart 3.11 syntax so the code generators can parse it. It still runs
with the newer Dart bundled with Flutter: Flutter 3.47.9 requires Dart 3.13 and
supplies 3.13.7. Raise the language version only when the generators support it,
then regenerate the code. Do not hide parser errors or edit generated files.

Some indirect dependencies are also held back by Flutter or other packages,
including Yaru's layout/window dependencies, file picker's `cross_file`, and
Flutter's `material_color_utilities`. Recheck
`flutter pub outdated --transitive` after each upgrade. Do not add indirect
dependencies to `pubspec.yaml` just to get newer versions.

## Upgrade checklist

Read the release notes. If the docs are outdated, check the installed package
source. Try major upgrades in a temporary directory first. Update `pubspec.yaml`
and `pubspec.lock` together.

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

Use `flutter pub upgrade --major-versions` to try major upgrades. Review changes
to equality, storage formats, and provider cleanup before accepting an upgrade.
The full test suite includes `test/core/riverbloc_contract_test.dart`, which
exercises production provider initialization, repository replacement, state
delivery, and disposal.

Record hardware, authorization, file-picker, and visual checks separately from
automated tests. Note which checks you did not run.

## Primary sources

- [Flutter stable release manifest](https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json)
- [Flutter SDK test pins](https://github.com/flutter/flutter/blob/3.47.9/packages/flutter_test/pubspec.yaml)
- [Flutter SDK tool changes](https://github.com/flutter/flutter/compare/3.47.4...3.47.9)
- [Equatable breaking changes](https://pub.dev/packages/equatable/changelog)
- [Hive generator metadata](https://pub.dev/api/packages/hive_ce_generator)
- [Build runner metadata](https://pub.dev/api/packages/build_runner)
- [Yaru release notes](https://pub.dev/packages/yaru/changelog)
