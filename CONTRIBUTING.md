# Contributing

## Prerequisites

- Flutter SDK (stable channel) — `flutter --version`
- `legion_linux` kernel module installed and loaded
- `legion_cli` installed and in PATH — `which legion_cli`
- A polkit agent running (required for privileged write operations)
- NVIDIA driver (optional, only needed for dGPU features)

### NixOS / direnv

If you use NixOS with direnv, a `shell.nix` or flake that provides Flutter and the required system libraries will be needed. The project does not include one — add to your own environment configuration.

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

## Issue tracking

This project uses `bd` (beads) for issue tracking.

```bash
bd list                        # see all open issues
bd show <id>                   # view issue details and acceptance criteria
bd ready                       # find issues with no unresolved blockers
```

## Adding a new feature

Follow these steps to add a new hardware feature page. Use an existing feature (e.g. `lib/features/dgpu/`) as a reference.

### 1. Plan

Write a plan document in `docs/plans/YYYY-MM-DD-<feature>.md` describing the layers, files, and test cases before writing code. See existing plan documents for the expected format.

### 2. Implement (TDD, layer by layer)

Work bottom-up through the stack. Write tests before implementation for each layer.

**Models** (`lib/features/<name>/models/`)
- `<name>_snapshot.dart` — plain data class, extends `Equatable`, constructor + `props`
- Any parser models (e.g. `DgpuProcess.parseNvidiaSmiOutput`) — write tests first

**State + Event** (`lib/features/<name>/bloc/`)
- `<name>_state.dart` — extends `Equatable`; use the `_unset` sentinel for nullable fields in `copyWith`; add computed getters (e.g. `isAvailable`)
- `<name>_event.dart` — `sealed class <Name>Event extends Equatable`; `final class` for each event

**Repository** (`lib/features/<name>/repository/`)
- `<name>_repository.dart` — depends on `LegionFrontendBridgeService`; unprivileged reads via `dart:io File`; privileged writes via `bridgeService.runPrivilegedCommand`
- Define a `<Name>RepositoryException` to wrap bridge errors
- See `docs/architecture/sysfs-vs-cli-access-audit.md` for which sysfs path and `legion_cli` subcommand to use for each feature

**BLoC** (`lib/features/<name>/bloc/<name>_bloc.dart`)
- Extends `Bloc<Event, State>`; uses `riverbloc` import
- Register one `on<>` handler per event
- Guard `isApplying` in write handlers; reload state after successful writes

**Provider** (`lib/features/<name>/providers/<name>_provider.dart`)
```dart
final <name>RepositoryProvider = Provider<...>((ref) {
  final bridge = ref.watch(legionBridgeServiceProvider);
  return <Name>Repository(bridgeService: bridge);
});

final <name>BlocProvider = BlocProvider.autoDispose<...>((ref) {
  final repository = ref.watch(<name>RepositoryProvider);
  return <Name>Bloc(repository: repository)..add(const <Name>Started());
});
```

**Navigation** (`lib/features/navigation/`)
- Add entry to `AppSection` enum in `models/app_section.dart`
- Add `label`, `icon`, and `yaruIcon` switch cases
- Add `case AppSection.<name>: return const <Name>Page();` in `NavigationShell._buildPage`

**View** (`lib/features/<name>/view/<name>_page.dart`)
- `ConsumerWidget`; watch the bloc provider; use `AppPageBody`, `AppSectionCard`, `AppRefreshButton`
- Privileged action buttons must call `confirmPrivilegedAction()` before dispatching events
- Show `PrivilegedActionNotice` widget near any privileged action buttons
- Gate deactivation sections with `if (state.isAvailable)`

### 3. Verify

```bash
flutter test
flutter analyze
```

All existing tests must still pass. New tests should cover state/copyWith, model parsing, and BLoC handlers.

### 4. Commit

Commit per layer with conventional commit messages:

```
feat(<name>): add <Name>Process model with parser
feat(<name>): add <Name>State and <Name>Event
feat(<name>): add <Name>Repository
feat(<name>): add <Name>Bloc
feat(<name>): register provider and add nav section
feat(<name>): add <Name>Page view
```

## Privileged commands

All writes go through `legion_cli`. The binary is invoked via `pkexec`:

```
pkexec /usr/bin/legion_cli <subcommand> [args...]
```

Two strategies are used depending on the feature (see `docs/architecture/sysfs-vs-cli-access-audit.md`):

| Strategy | Example |
|---|---|
| `set-feature <FeatureName> <value>` | `set-feature PlatformProfile quiet` |
| Named subcommand | `batteryconservation-enable` |
| Grouped subcommand | `boot-logo enable /path/to/image` |

Use `bridgeService.runPrivilegedCommand(method: '...', args: [...])` — do not call `LegionCliService` directly from a repository.

## Troubleshooting

**`legion_cli` not found**
```bash
which legion_cli
# if missing: install the legion_linux Python package
pip install /path/to/LenovoLegionLinux/python/legion_linux
```

**Permission denied on write**
- A polkit agent must be running (`gnome-polkit-agent`, `lxpolkit`, `polkit-kde-agent`, etc.)
- The polkit policy from `legion_cli.policy` must be installed in `/usr/share/polkit-1/actions/`

**Sysfs file not found**
- The `legion_linux` kernel module may not be loaded: `sudo modprobe legion_linux`
- The feature may not be supported on your hardware model

**Tests fail with `legion_cli not found`**
- Tests mock all I/O and should not call `legion_cli`. If a test invokes the real CLI, it is testing at the wrong layer — use `mocktail` to mock the repository or bridge service instead.
