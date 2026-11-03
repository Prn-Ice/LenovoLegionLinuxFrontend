# Contributing

## Prerequisites

- Flutter SDK (stable channel) — `flutter --version`
- `legion_linux` kernel module installed and loaded
- `legion_cli` installed and in PATH — `which legion_cli`
- A polkit agent running (required for privileged write operations)
- NVIDIA driver (optional, only needed for dGPU features)

### NixOS / direnv

The project has no local flake. `.envrc` uses the shared flake at
`/home/prnice/Projects/personal/nix_flakes/flutter_flake#linux`. It supplies Flutter,
Dart, and Linux build dependencies without the default shell's Android SDK and
emulator downloads. If your checkout lives elsewhere, adjust
that path to your own environment. SDK changes in the shared flake affect other
projects using it; update it deliberately rather than running `flutter upgrade`
against the read-only Nix store.

See [dependency notes](docs/dependencies.md) for retained constraints and the
upgrade procedure. Read the [project code patterns](.agents/skills/code-patterns/SKILL.md)
before implementation or review; prefer existing, readable patterns to new layers.

## Dev environment setup

```bash
git clone git@github.com:Prn-Ice/LenovoLegionLinuxFrontend.git
cd LenovoLegionLinuxFrontend
flutter pub get
```

## Run

```bash
flutter run -d linux
```

Flutter hot-reload (`r`) and hot-restart (`R`) both work during development.

## Test

```bash
flutter test                    # run all tests
flutter test --reporter=expanded  # verbose output
flutter test test/features/fans/  # single feature
flutter analyze                 # static analysis
```

Tests run without a connected device or kernel module — all I/O is unit-tested with mocks.

The shared Linux shell also includes Polkit headers for native service checks:

```bash
cmake -S telemetry -B build/native -G Ninja -DBUILD_LEGION_CONTROL_SERVICE=ON
cmake --build build/native --target legion_telemetry_service legion_control_service package_power_sampler_test control_commands_test
ctest --test-dir build/native --output-on-failure
```

These compile both services and test telemetry parsing and the control-command
allow-list. They do not install services or authorize real hardware writes.

## Issue tracking

This project uses `bd` (beads) for issue tracking.

```bash
bd list                        # see all open issues
bd show <id>                   # view issue details and acceptance criteria
bd ready                       # find issues with no unresolved blockers
```

## Adding a new feature

Follow these steps to add a new hardware feature page. Read the
[Riverbloc usage guide](.agents/skills/code-patterns/references/riverbloc.md),
[examples](.agents/skills/code-patterns/references/riverbloc-patterns.md),
[testing guide](.agents/skills/code-patterns/references/testing.md), and
[Flutter UI guide](.agents/skills/code-patterns/references/flutter-ui.md) as relevant.
Use existing features as context, not proof that every older pattern is current.

### 1. Plan

Describe the intended behavior, affected layers, and useful tests in the live
Beads issue. Historical plans under `docs/plans/` provide context, not current
instructions. Add only the layers the feature actually needs.

### 2. Implement and test the behavior

Work bottom-up where the feature needs those layers. Write useful logic tests
before implementation; do not create empty layers or tests of framework guarantees.

**Models** (`lib/features/<name>/models/`)
- `<name>_snapshot.dart` — plain immutable data; use `Equatable` when value equality is part of the contract, not as a mandatory wrapper
- Any parser models (e.g. `DgpuProcess.parseNvidiaSmiOutput`) — write tests first

**State + Event** (`lib/features/<name>/bloc/`)
- `<name>_state.dart` — extends `Equatable`; use the `_unset` sentinel for nullable fields in `copyWith`; add computed getters (e.g. `isAvailable`)
- `<name>_event.dart` — `sealed class <Name>Event extends Equatable`; `final class` for each event

**Repository** (`lib/features/<name>/repository/`)
- `<name>_repository.dart` — follow the closest current feature; inject read services and the typed `LegionControlClient` for privileged writes
- Wrap errors when doing so adds useful feature context; do not add a forwarding layer solely to rename an exception
- See `docs/architecture/sysfs-vs-cli-access-audit.md` for which sysfs path and `legion_cli` subcommand to use for each feature

**BLoC** (`lib/features/<name>/bloc/<name>_bloc.dart`)
- Extends `Bloc<Event, State>`; uses `riverbloc` import
- Keep handlers focused; choose and test concurrency deliberately. Separate `on<>` registrations do not share a queue
- Guard repeated writes and reload authoritative state after success. An `isApplying` flag alone does not order writes against refresh/poll handlers

**Provider** (`lib/features/<name>/providers/<name>_provider.dart`)
```dart
final featureRepositoryProvider = Provider<FeatureRepository>((ref) {
  final controlClient = ref.watch(legionControlClientProvider);
  return FeatureRepository(controlClient: controlClient);
});

final featureBlocProvider = BlocProvider.autoDispose<FeatureBloc, FeatureState>((ref) {
  final repository = ref.watch(featureRepositoryProvider);
  return FeatureBloc(repository: repository)..add(const FeatureStarted());
});
```

This is a naming template; inject the dependencies the feature really uses.
Initialize once per instance. Widgets watch `featureBlocProvider` for state and
read `featureBlocProvider.bloc` inside action callbacks. The provider owns its
Bloc's disposal; do not close it again from a widget.

**Navigation** (`lib/features/navigation/`)
- Add entry to `AppSection` enum in `models/app_section.dart`
- Add `label`, `icon`, and `yaruIcon` switch cases
- Add `case AppSection.<name>: return const <Name>Page();` in `NavigationShell._buildPage`

**View** (`lib/features/<name>/view/<name>_page.dart`)
- `ConsumerWidget` or `ConsumerStatefulWidget`; watch state and compose visible regions in `AppPageBody`. Use `SurfaceCard` and the page template's shared primitives; the shell owns page titles and refresh actions
- Privileged action buttons must call `confirmPrivilegedAction()` before dispatching events
- Show `PrivilegedActionNotice` widget near any privileged action buttons
- Gate controls on actual backend capabilities, including partial/unavailable support; do not invent values or require a uniform state field solely to match a template

### 3. Verify

```bash
flutter test
flutter analyze
```

All existing tests must still pass. Add meaningful parser/state/handler tests,
provider lifetime checks, and UI journeys for the behavior changed. See the
testing guide rather than imposing a test-per-getter or coverage quota.

### 4. Commit

Use conventional commit messages for cohesive, reviewable changes. Split by
layer when it helps a larger change, not to create empty layers or require a
series of incomplete commits. For example:

```
feat(fans): validate and apply a fan curve with readback
fix(power): preserve edited limits when refresh completes
test(settings): cover provider replacement during confirmation
```

## Privileged commands

All writes go through the typed `io.github.prnice.LegionControl1` system-bus API. The root service validates each operation against a fixed allow-list before invoking `legion_cli` or `systemctl`; it never accepts an arbitrary executable, argument vector, service unit, or caller-controlled root file path.

The frontend's `LegionControlClient` maps the repository command vocabulary to typed D-Bus methods. `Authorize` triggers Polkit once for the frontend's unique D-Bus sender, and the service revokes that authorization when the sender disconnects.

Two strategies are used depending on the feature (see `docs/architecture/sysfs-vs-cli-access-audit.md`):

| Strategy | Example |
|---|---|
| `set-feature <FeatureName> <value>` | `set-feature PlatformProfile quiet` |
| Named subcommand | `batteryconservation-enable` |
| Grouped subcommand | `boot-logo enable /path/to/image` |

Prefer typed `LegionControlClient` methods for new operations. Existing bridge
callers may retain `bridgeService.runPrivilegedCommand(method: '...', args: [...])`
as a compatibility vocabulary that maps to the allow-listed D-Bus API; it is not
permission to execute arbitrary commands. Do not launch privileged CLI writes
directly from a repository or add another privilege-elevation path.

When adding a writable feature, extend and test both the Dart mapping and the C++ allow-list. Do not add a generic command method or a privilege-elevation fallback.

## Troubleshooting

**`legion_cli` not found**
```bash
which legion_cli
# if missing: install the legion_linux Python package
pip install /path/to/LenovoLegionLinux/python/legion_linux
```

**Permission denied on write**
- A polkit agent must be running (`gnome-polkit-agent`, `lxpolkit`, `polkit-kde-agent`, etc.)
- `legion-control.service` must be running
- The supplied D-Bus policy and `io.github.prnice.legion-control.policy` must be installed

**Sysfs file not found**
- The `legion_linux` kernel module may not be loaded: `sudo modprobe legion_linux`
- The feature may not be supported on your hardware model

**Tests fail with `legion_cli not found`**
- Tests mock all I/O and should not call `legion_cli`. If a test invokes the real CLI, it is testing at the wrong layer — use `mocktail` to mock the repository or bridge service instead.
