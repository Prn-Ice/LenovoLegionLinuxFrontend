# Dependencies

Use compatible stable packages and commit `pubspec.lock`.

## Flutter and build tools

- Flutter stable **3.50.0** or newer; CI pins 3.50.0 with Dart 3.14.0
- A Linux desktop compiler, CMake, Ninja, and pkg-config
- GTK development headers and Flutter's native development libraries
- GLib/GIO development files for native services
- Polkit development files for control-service builds
- Bash, GNU coreutils, and jq for shell tools and their tests

See [contributor setup](../CONTRIBUTING.md) for installation commands and optional
Nix/direnv configuration.

Project-owned tools use Dart, Nix, or shell, not Python. The NixOS VM test
driver and some upstream build tools still use Python internally. Their required
driver calls stay in Nix test definitions; test scenarios run shell scripts in
the guest. The administrator-installed LenovoLegionLinux CLI is an external
backend and may also use Python. Keep its environment-isolation checks intact.
Historical audits name upstream Python classes and files as evidence, not as
project runtime requirements. The language rule in `AGENTS.md` governs new code.

Flutter 3.50 uses the standalone `material_ui` package. Yaru 12 supplies matching
themes, so the app and tests use those imports together. Dart's supported
`migrate_design_widgets` fix updates the imports. The app uses Dart 3.14 syntax;
the generator versions below support it.

The Nix SDK uses the existing Nixpkgs builder. `packaging/nix/flutter.json` pins
the official source, Dart and engine artifact hashes, plus the tool dependency
lock from the official SDK. `packaging/nix/flutter-tools.patch` adapts Nixpkgs'
cache and host-platform tool patches to moved methods and restores an import
required by its Gradle patch. These changes leave the engine binary intact.
Use upstream packaging when Nixpkgs supplies Flutter 3.50.

Flutter's Linux task runner can dispatch queued work after its owner is freed
during window shutdown ([upstream report](https://github.com/flutter/flutter/issues/193742)).
The native application retains its engine until `MyApplication.dispose`, after
`g_application_run` returns. This small lifetime workaround was approved on
2026-11-12; it requires no change to installation or launch. Remove it after a
compatible stable SDK includes [the upstream fix](https://github.com/flutter/flutter/pull/194525)
and repeated window-close checks pass (`lllf-dt0.5.13`).


Flutter 3.50 package qualification remains blocked by Linux renderer teardown
(`lllf-dt0.5.16`). The NixOS AppImage can exit while its raster thread still uses
Mesa; explicitly destroying the retained window instead can abort in
`g_mutex_clear`. The experimental cleanup was rejected. Upstream
[renderer lifetime work](https://github.com/flutter/flutter/pull/193533) addresses
resource cleanup across the GTK and raster threads, but is not in this stable
SDK. Keep the published launch instructions and close assertions intact; a
passing Dart suite does not qualify a desktop package. See the
[shutdown evidence and follow-up](linux-shutdown.md).

The native Linux app journeys use Flutter's SDK-provided `integration_test` as a
development dependency. It follows the installed Flutter version. These tests
need no external desktop automation tool or production test-mode flag. See
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

### Test dependencies and code generation

Flutter 3.50's `flutter_test` pins `test_api` to 0.7.14. `bloc_test` brings in
`test`; the compatible versions are `test` 1.32.0 and `test_core` 0.6.20.
`test` 1.33.0 requires `test_api` 0.7.15. Keep Flutter's pins rather than
overriding them.

The generator conflict is resolved. Use these compatible stable releases:

| Package | Resolved version |
| --- | --- |
| `hive_ce_generator` | 1.12.1 |
| `build_runner` | 2.17.1 |
| `analyzer` | 14.7.0 |

Let Pub choose indirect build and formatter dependencies. Run the real generator
after changes; do not hide parser errors or edit generated files.

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
- [Flutter SDK test pins](https://github.com/flutter/flutter/blob/3.50.0/packages/flutter_test/pubspec.yaml)
- [Flutter SDK tool changes](https://github.com/flutter/flutter/compare/3.47.9...3.50.0)
- [Equatable breaking changes](https://pub.dev/packages/equatable/changelog)
- [Hive generator metadata](https://pub.dev/api/packages/hive_ce_generator)
- [Build runner metadata](https://pub.dev/api/packages/build_runner)
- [Yaru release notes](https://pub.dev/packages/yaru/changelog)
