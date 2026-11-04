# Contributing

Thanks for helping improve Legion Linux Frontend. Open a GitHub issue to report
a bug, request support, or discuss a change. Pull requests are welcome; link the
related issue when there is one. A laptop, kernel module, CLI, and installed
services are not needed for ordinary documentation, UI, parser, or test work.

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

Package names can vary by distribution release. Android SDK components are not
needed for this Linux app.

```bash
git clone https://github.com/Prn-Ice/LenovoLegionLinuxFrontend.git
cd LenovoLegionLinuxFrontend
flutter --version
flutter pub get
```

For an optional Nix/direnv setup, set `LLLF_DEV_FLAKE` to a flake reference that
provides Flutter and Linux build tools, then run `direnv allow`.

## Test without hardware

```bash
flutter test
flutter analyze
```

Tests use fakes, mocks, and fixtures; they should not require a connected laptop,
kernel module, `legion_cli`, system bus service, or privileged writes. Keep tests
at the external boundary and do not make ordinary test runs depend on host
hardware. To build and test native service code without installing it:

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

The live application currently requires `legion_cli` in `PATH`: constructing
`LegionCliService` fails if it cannot find the executable. Once the backend is
installed, launch the application with:

```bash
flutter run -d linux
```

Hardware testing also requires the kernel module, backend, D-Bus/Polkit policy,
and service. See the [model-support guide](docs/model-support.md) for collecting
diagnostics and reporting tested features.

## Make a change

Start with the closest feature and the project [code patterns](.agents/skills/code-patterns/SKILL.md).
Keep changes focused, preserve the sysfs/HID/D-Bus hardware boundaries, and add
tests that reproduce behavior without a device. For UI work, follow
[`docs/page-template.md`](docs/page-template.md) and
[`docs/error-and-feedback-standard.md`](docs/error-and-feedback-standard.md).

Before opening a pull request, run relevant tests and `flutter analyze`; run the
native checks above when native files changed. In the pull request, describe the
behavior changed, commands run and their results, and any hardware checks not
performed. For model support changes, include the evidence and a tested-model
entry.

## Privileged operations

Privileged writes go through typed `LegionControlClient` methods and the native
allow-list. When adding a writable feature, update and test both the Dart mapping
and the C++ validation. Do not launch privileged CLI writes from a repository,
add an arbitrary command interface, or introduce a privilege-elevation fallback.
