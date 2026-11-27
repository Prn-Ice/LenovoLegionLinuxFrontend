# Contributing

Report bugs and discuss changes in GitHub issues. Link the related issue in your
pull request. Most development and tests do not need Legion hardware or installed
services.

## Set up

- Flutter stable 3.50.0 or newer ([dependency notes](docs/dependencies.md))
- CMake 3.16 or newer, Ninja, a C/C++ compiler, and pkg-config
- GTK 3 and C++ standard-library development files
- GLib/GIO development files for native service tests
- Polkit development files for the bundled helper and control-service tests
- Bash, GNU coreutils, and jq for tooling tests and packaging scripts
- Git and OpenSSH (`ssh-keygen`) for isolated Git fixtures
- `dpkg-deb` and SquashFS tools for package-payload tests

Linux builds include the privileged control helper. Nix development builds also
need `patchelf` to retain its runtime library paths.

Follow the [Flutter Linux setup guide](https://docs.flutter.dev/platform-integration/linux/setup).
On Debian/Ubuntu, install the build dependencies with:

```bash
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev libstdc++-12-dev libglib2.0-dev xvfb xauth jq dpkg-dev squashfs-tools git openssh-client
```

Package names vary by distribution. You do not need the Android SDK.

```bash
git clone https://github.com/Prn-Ice/LenovoLegionLinuxFrontend.git
cd LenovoLegionLinuxFrontend
flutter --version
flutter pub get
git config --local core.hooksPath .githooks
```

The pre-push hook runs generation, analysis, and app tests in the current
worktree. It also runs tooling tests when the branch or local edits change
tooling, packaging, native code, dependencies, or test infrastructure. It compares
the worktree with the branch point on `origin/main`, including staged, unstaged,
and untracked files. Release tags and worktrees without a usable `origin/main`
run every test. Work in a clean worktree so these checks reflect the commit you
push.

A failed command stops the push. Enable the hook in every clone; Git does not
install repository hooks when cloning. Some tests require Linux.

Merging a PR into `main` does not publish a release. Pushing a matching `v*`
tag starts the release workflow, which checks the tag, builds the packages,
runs acceptance tests and publishes the verified artifacts.

Run `nix develop` for the project's development shell, or `direnv allow` to load
it automatically with nix-direnv.

See [the Nix frontend build](docs/nix.md) for the packaged app, source archive,
dependency metadata updates, and disposable VM acceptance check.

### Rebuild after changing the Nix environment

After updating `flake.lock` or switching development shells, CMake can retain
library paths from the previous environment. A runtime search-path cycle that
lists two GLib versions indicates mixed library paths. Enter the current shell
and rebuild from a clean cache:

```bash
nix develop
flutter clean
flutter pub get --enforce-lockfile
flutter run -d linux
```

The build should resolve one GLib version and launch without the search-path
cycle warning. Close any running app instance first so it releases its data files.

## Test without hardware

```bash
flutter test
flutter analyze
```

Use fake services and sample data so tests run without hardware, installed
services, or administrator access.

Tooling tests exercise Git, release scripts, and package formats. Git fixtures
use disposable repositories, isolated user configuration, empty hook/template
directories, and unsigned commits. The tag test uses its own temporary signing
key and local remote.

For an unrelated app change, run only app tests:

```bash
flutter test --exclude-tags tooling
```

To check tooling changes, run `flutter test --tags tooling`. Plain `flutter test`
and CI still run both groups.

### Linux app integration journey

See the [native coverage matrix](docs/native-journey-coverage.md) for the covered
sections, safe I/O boundaries, quick smoke command, restart checks, and limits.

From a Linux desktop session, run:

```bash
flutter pub get --enforce-lockfile
bash tool/ci/test_linux_journeys.sh
```

The `app_test.dart` entrypoint runs the native app scenarios. The battery journey
cancels and applies the Dashboard's Battery health confirmation, then navigates
to Battery and checks Conservation mode without refreshing. It then disables
conservation on Battery and verifies Dashboard readback. Polling is paused for
this journey so it cannot hide stale state. The recovery journey
checks retry after permission-denied, unavailable-service, and failed-command
responses, plus verifies that the switch stays disabled and unchanged until a
controlled pending write completes.

Power journeys select Performance, verify Power and Dashboard readback, and
check that selecting an AC-only mode on battery sends no privileged request.
Power-limit journeys stage two slider edits without writing, revert them, then
apply them together and verify temporary sysfs and page readback. A rejected
second write restores the first value and leaves the edits available for retry.
Non-Custom mode, battery power, unknown AC status, and unsupported limits send no
privileged requests. Polling is paused so it cannot repair missing readback.
Rapid-charging journeys cancel and apply the Power confirmation while on battery,
then check confirmed readback. Battery has no rapid-charging readout: its Refresh
action reloads a simulated firmware change into shared state, and returning to
Power verifies the visible switch. A failed write preserves the confirmed value;
a controlled pending retry keeps the switch disabled and unchanged until
completion. Unsupported devices expose no rapid-charging control.
The keyboard journey saves a Lighting profile, makes a different manual edit,
assigns the saved profile to Balanced in Automation, and verifies the saved
colors are applied. It also checks that clearing the assignment leaves lighting
unchanged. The mode-switching journey checks assigned profiles while navigating
away from Automation and preserves manual edits during same-mode refreshes.
The keyboard recovery journeys return failed OpenRGB process results on Lighting
and Automation. They check that errors appear, failed writes preserve the last
successful colors and saved configuration, and retry stays disabled until a
pending command completes.

The missing-profile journey deletes an assigned profile and clears its missing
assignment without another RGB command. The Fans journey cancels a preset
confirmation, then applies the preset and checks its curve readback through the
real repository. Polling is paused so it cannot hide a missing write readback.
The curve-editing journeys use the precise CPU/GPU controls to change temperature
and speed, check that edits stay within neighbouring points, cancel save without
writing, then apply and verify the full table and visible readback. Rejected
writes and accepted commands with unchanged readback preserve the draft for
retry. The fixture accepts only this synthetic edited table; it does not parse
arbitrary YAML or qualify a real controller.

The runner then starts two separate native app processes to check persistence.
The first saves a profile and its assignment, makes a different manual edit, and
exits. The second reopens the same temporary Hive/config data and verifies the
assigned profile is restored. The processes record distinct IDs. The runner
removes its temporary data on completion or failure.

The control-helper scenario uses the real Linux method channel to check that
an invalid endpoint is rejected before connection. It starts no helper. The native
discovery scenario rejects caller-selected CLI paths before inspecting the host.
The hardware-access journey opens fresh Settings, checks that the authorization
selector is gone, and verifies that opening the page requests no authorization.
After the journeys, check native method names, argument types, and payload limits
with:

```bash
flutter build linux --debug --no-pub
cmake --build build/linux/x64/debug --target control_channel_test
xvfb-run -a build/linux/x64/debug/runner/control_channel_test
```

To run only the journeys in the first app process:

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
fixture and rejects other operations. Live sensors use fixed repository results
because they contain direct host reads. CLI
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
  bash tool/ci/test_linux_journeys.sh
```

The Linux native integration journey runs as a separate CI job with the same
Flutter SDK pin and Linux desktop dependencies. It runs the complete sequence
in a fresh checkout under Xvfb and retains its command log when it fails.
Headless runs need Xvfb, `xauth`, and `gsettings-desktop-schemas` for Yaru's GNOME
settings reads. CI uses an in-memory settings backend. The runner does not
capture screenshots for these tests.

Plain `flutter test` still runs the separate unit/widget suite under `test/`.

To build and test the native helper without installing it:

```bash
cmake -S control -B build/native -G Ninja -DBUILD_CONTROL_HELPER=ON
cmake --build build/native --target legion_control_helper package_power_sampler_test control_commands_test managed_command_test executable_snapshot_test helper_lifetime_test control_peer_test trusted_executable_test helper_cli_test
ctest --test-dir build/native --output-on-failure
```

For the AppImage control experiment, run the
[hardware-free control-helper probe](docs/architecture/control-helper.md#hardware-free-prototype).
It tests a private D-Bus connection with simulated authorization and a synthetic
backend, using an opt-in native build.

To test administrator startup from an immutable helper snapshot:

```bash
nix build .#checks.x86_64-linux.helper-bootstrap --print-build-logs
```

This separate disposable VM uses real systemd and Polkit with deterministic test
policies. The startup probe uses a synthetic CLI and refuses to run on the host.
See the [startup experiment](docs/architecture/control-helper.md#administrator-startup-experiment)
for its trust boundary and remaining checks.

To build and test the production helper with Ubuntu 22.04's libraries, follow
the [Ubuntu helper tests](docs/architecture/control-helper-tests.md).
It uses a synthetic CLI and records the image, source, package versions, and results.

To build and test the actual AppImage through FUSE and extraction, follow
[the AppImage instructions](docs/appimage.md). Its acceptance VM uses synthetic
hardware and verifies desktop launch without a JVM.

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

Use [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) for
new commits and PR titles: `type(scope): description`. The scope is optional.
Choose `feat`, `fix`, `perf`, `refactor`, `docs`, `test`, `build`, `ci`, `chore`,
`style`, or `revert`. For example:

```text
fix(fans): preserve the curve after a failed write
ci: reuse package inputs across builds
feat(control)!: require the new helper protocol
```

Use `!` for breaking changes and explain the migration in the commit body.
Release notes also recognize `BREAKING CHANGE:` and `BREAKING-CHANGE:` footers.
Write subjects as release-note entries: say what changed, not just "update code".

The required `Conventional Commits` check validates PR titles, including title
edits, and every new non-merge commit subject. It excludes existing base history.
PRs use squash merges with the PR title as the default commit subject. Keep that
subject conventional when merging. Existing history is preserved.

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
