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
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev libstdc++-12-dev libglib2.0-dev libpolkit-gobject-1-dev xvfb xauth
```

Package names vary by distribution. You do not need the Android SDK.

```bash
git clone https://github.com/Prn-Ice/LenovoLegionLinuxFrontend.git
cd LenovoLegionLinuxFrontend
flutter --version
flutter pub get
```

Run `nix develop` for the project's development shell, or `direnv allow` to load
it automatically with nix-direnv.

## Test without hardware

```bash
flutter test
flutter analyze
```

Use fake services and sample data so tests run without hardware, installed
services, or administrator access.

### Linux app integration journey

From a Linux desktop session, run:

```bash
flutter pub get --enforce-lockfile
bash tool/test_linux_journeys.sh
```

The `app_test.dart` entrypoint registers twelve scenarios. The battery journey
cancels and applies the Dashboard's Battery health confirmation, then navigates
to Battery and checks Conservation mode without refreshing. It then disables
conservation on Battery and verifies Dashboard readback. Polling is paused for
this journey so it cannot hide stale state. The recovery journey
checks retry after permission-denied, unavailable-service, and failed-command
responses, plus verifies that the switch stays disabled and unchanged until a
controlled pending write completes.

Power journeys select Performance, verify Power and Dashboard readback, and
check that selecting an AC-only mode on battery sends no privileged request.
The keyboard journey saves a Lighting profile, makes a different manual edit,
assigns the saved profile to Balanced in Automation, and verifies the saved
colors are applied. It also checks that clearing the assignment leaves lighting
unchanged. The mode-switching journey checks assigned profiles while navigating
away from Automation and preserves manual edits during same-mode refreshes.
The keyboard recovery journeys return failed OpenRGB process results on Lighting
and Automation. They check that errors appear, failed writes preserve the last
successful colors and saved configuration, and retry stays disabled until a
pending command completes.

The runner then starts two separate native app processes to check persistence.
The first saves a profile and its assignment, makes a different manual edit, and
exits. The second reopens the same temporary Hive/config data and verifies the
assigned profile is restored. The processes record distinct IDs. The runner
removes its temporary data on completion or failure.

The portable-control scenario uses the real Linux method channel to check that
an invalid endpoint is rejected before connection. It starts no helper. After
the journeys, check native method names, argument types, and payload limits with:

```bash
flutter build linux --debug --no-pub
cmake --build build/linux/x64/debug --target portable_control_channel_test
build/linux/x64/debug/runner/portable_control_channel_test
```

To run only the twelve scenarios in the first app process:

```bash
flutter test integration_test/app_test.dart -d linux --no-pub
```

Do not run concurrent Flutter commands in the same checkout while this journey
is running; they can interfere with its native build and debug connection.

This builds and opens the actual GTK/Flutter application window and drives the
app through Flutter's integration-test binding, not the widget-test host. It uses
the app widget and navigation shell with test overrides; it does not exercise all
application sections or full production `main` initialization. Flutter-driven
interaction does not move your OS pointer or automate native Polkit dialogs.

The test backend lives only under `integration_test/`. It redirects sysfs/proc
reads and the real `AutomationRepository` config file to temporary fixture
storage. The real providers, Blocs, repositories, bridge, and control client are
used for the setting under test. A fake control transport writes only the
fixture and rejects other operations. System service status and live sensors
use fixed repository results because they contain direct host reads. CLI
execution, display access, and system telemetry are blocked. HID and OpenRGB
access are blocked by default; the keyboard journeys supply OpenRGB process
results to the real CLI service and confine Spectrum discovery to temporary
fixture paths.
Hive data and keyboard assignments are temporary.

No sudo, installed service, or Legion hardware is needed. This journey does not
verify real D-Bus policy, Polkit authorization, firmware, or hardware changes.
It requires the normal Linux build dependencies and an available display. On a
headless Linux machine, install Xvfb (for example, `sudo apt-get install xvfb` on
Debian/Ubuntu) and run:

```bash
flutter pub get --enforce-lockfile
xvfb-run -a --server-args='-screen 0 1280x800x24' \
  bash tool/test_linux_journeys.sh
```

The Linux native integration journey runs as a separate CI job with the same
Flutter SDK pin and Linux desktop dependencies. It runs the complete sequence
in a fresh checkout under Xvfb and retains its command log when it fails.
Headless runs need Xvfb, `xauth`, and `gsettings-desktop-schemas` for Yaru's GNOME
settings reads. CI uses an in-memory settings backend. The runner does not
capture screenshots for these tests.

Plain `flutter test` still runs the separate unit/widget suite under `test/`.

To build and test native service code without installing it:

```bash
cmake -S telemetry -B build/native -G Ninja -DBUILD_LEGION_CONTROL_SERVICE=ON
cmake --build build/native --target legion_telemetry_service legion_control_service package_power_sampler_test control_commands_test graphics_boot_service_test managed_command_test executable_snapshot_test portable_lifetime_test portable_peer_test trusted_executable_test
ctest --test-dir build/native --output-on-failure
```

For the AppImage control experiment, run the
[hardware-free portable-control probe](docs/architecture/portable-control.md#hardware-free-prototype).
It tests a private D-Bus connection with simulated authorization and a synthetic
backend, using an opt-in native build.

To check backend process cleanup with real systemd, run the disposable VM test:

```bash
nix build .#checks.x86_64-linux.control-lifecycle --print-build-logs
```

This uses QEMU/KVM and synthetic backend commands inside NixOS. See
[backend process containment](docs/architecture/portable-control.md#backend-process-containment)
for the lifecycle cases it covers.

To test administrator startup from an immutable helper snapshot:

```bash
nix build .#checks.x86_64-linux.portable-bootstrap --print-build-logs
```

This separate disposable VM uses real systemd and Polkit with deterministic test
policies. The startup probe uses a synthetic CLI and refuses to run on the host.
See the [startup experiment](docs/architecture/portable-control.md#administrator-startup-experiment)
for its trust boundary and remaining checks.

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
