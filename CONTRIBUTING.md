# Contributing

Report bugs and discuss changes in GitHub issues. Link the related issue in your
pull request. Most development and tests do not need Legion hardware or installed
services.

## Set up

- Flutter stable 3.47.9 or newer ([dependency notes](docs/dependencies.md))
- CMake, Ninja, a C/C++ compiler, and pkg-config
- GTK 3 and C++ standard-library development files
- GLib/GIO development files for native service tests
- Polkit development files for control-service builds

Follow the [Flutter Linux setup guide](https://docs.flutter.dev/platform-integration/linux/setup).
On Debian/Ubuntu, install the build dependencies with:

```bash
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev libstdc++-12-dev libglib2.0-dev libpolkit-gobject-1-dev
```

Package names vary by distribution. You do not need the Android SDK.

```bash
git clone https://github.com/Prn-Ice/LenovoLegionLinuxFrontend.git
cd LenovoLegionLinuxFrontend
flutter --version
flutter pub get
```

If you use Nix and direnv, set `LLLF_DEV_FLAKE` to a flake with Flutter and Linux
build tools. Then run `direnv allow`.

## Test without hardware

```bash
flutter test
flutter analyze
```

Use fake services and sample data so tests run without hardware, installed
services, or administrator access.

To build and test native service code without installing it:

```bash
cmake -S telemetry -B build/native -G Ninja -DBUILD_LEGION_CONTROL_SERVICE=ON
cmake --build build/native --target legion_telemetry_service legion_control_service package_power_sampler_test control_commands_test graphics_boot_service_test
ctest --test-dir build/native --output-on-failure
```

To capture screenshots for visual review:

```bash
flutter test test/visual_handoff_review_test.dart --dart-define=VISUAL_REVIEW=true
```

Inspect the captured images before submitting UI changes.

## Hardware and model support

Install `legion_cli` and make sure it is in `PATH`, then start the app:

```bash
flutter run -d linux
```

Hardware testing also requires the kernel module, backend, D-Bus/Polkit policy,
and service. See the [model-support guide](docs/model-support.md) for collecting
diagnostics and reporting tested features.

## Make a change

Start with the closest feature and the project [code patterns](.agents/skills/code-patterns/SKILL.md).
Keep changes focused. Use the existing hardware services and add tests that run
without a device. For UI work, follow
[`docs/page-template.md`](docs/page-template.md) and
[`docs/error-and-feedback-standard.md`](docs/error-and-feedback-standard.md).

Before opening a pull request, run relevant tests and `flutter analyze`; run the
native checks above when native files changed. In your pull request, say what
changed, what you tested, and what you could not test. For model support changes,
include the evidence and a tested-model entry.

## Privileged operations

Use `LegionControlClient` for changes that need administrator access. Add and test
the operation in both Dart and the C++ service. Do not run privileged commands
directly or add an interface that accepts arbitrary commands.
