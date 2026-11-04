# Contributing

Thanks for helping improve Legion Linux Frontend. Open a GitHub issue to report
a bug, request support, or discuss a change. Pull requests are welcome; link the
related issue when there is one. A laptop, kernel module, CLI, and installed
services are not needed for ordinary documentation, UI, parser, or test work.

## Set up

Install Flutter stable (3.47.9 or newer; see [dependency notes](docs/dependencies.md))
and the Linux desktop prerequisites for Flutter: CMake, Ninja, a C/C++ compiler,
pkg-config, GTK 3 development headers, and Linux desktop development libraries.
For native service tests, also install GLib/GIO development files; control-service
builds need Polkit development files. Use your distribution's package names and
Flutter's Linux desktop setup guidance. You do not need Android SDK components
for this Linux app.

```bash
git clone https://github.com/Prn-Ice/LenovoLegionLinuxFrontend.git
cd LenovoLegionLinuxFrontend
flutter --version
flutter pub get
```

The repository does not require Nix or direnv. Optionally, set
`LLLF_DEV_FLAKE` to a flake reference that provides Flutter and Linux build tools,
then run `direnv allow`. `.envrc` does not select a maintainer-specific path or
update a shared SDK.

## Run and test without hardware

```bash
flutter test
flutter analyze
flutter run -d linux
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

These commands compile and test native code; they do not install services or
authorize hardware writes. An opt-in rendered review is available with:

```bash
flutter test test/visual_handoff_review_test.dart --dart-define=VISUAL_REVIEW=true
```

Inspect its captured images; a passing capture test alone does not prove visual
quality or hardware behavior.

## Hardware and model support

Install the kernel module, backend, D-Bus/Polkit policy, and service only when
you intentionally want to test on supported hardware. Read the
[model-support guide](docs/model-support.md) first. Keep unknown features marked
unknown until there is evidence, and never describe a model as fully supported
based on its name alone.

## Make a change

Start with the closest feature and the project [code patterns](.agents/skills/code-patterns/SKILL.md).
Keep changes focused, preserve the sysfs/HID/D-Bus hardware boundaries, and add
tests that reproduce behavior without a device. For UI work, follow
[`docs/page-template.md`](docs/page-template.md) and
[`docs/error-and-feedback-standard.md`](docs/error-and-feedback-standard.md).

Before opening a pull request, run relevant tests and `flutter analyze`; run the
native checks above when native files changed. In the pull request, describe the
behavior changed, commands run and their results, and any hardware checks not
performed. Never claim a real device check that you did not do. If the change
adds or corrects model support, include the evidence and a tested-model entry.

## Privileged operations

Privileged writes go through typed `LegionControlClient` methods and the native
allow-list. When adding a writable feature, update and test both the Dart mapping
and the C++ validation. Do not launch privileged CLI writes from a repository,
add an arbitrary command interface, or introduce a privilege-elevation fallback.
