# Architecture Overview

This document explains how the Legion Linux Frontend is structured end-to-end: how it reads hardware state, how it writes settings, how the UI reacts to state changes, and how the codebase is organised.

---

## System Context

The frontend is a Flutter desktop application for Linux. It does **not** contain any kernel or hardware code. Instead it sits on top of two external surfaces provided by the `legion_linux` kernel module:

```
┌─────────────────────────────────┐
│   Legion Linux Frontend (Dart)  │
│                                 │
│  reads ──────────────────────► sysfs   (direct, unprivileged)
│  writes ─► pkexec legion_cli ► sysfs   (privileged, via polkit)
└─────────────────────────────────┘
         ▲
    legion_linux kernel module
    exposes /sys/devices/... nodes
```

**Reads** are done directly from sysfs using `dart:io File.readAsString()`. No privilege required; no process spawned.

**Writes** always go through `legion_cli` (a Python CLI tool installed system-wide), invoked via `pkexec` for privilege elevation. The polkit agent shows the user an authentication dialog before any write completes.

The frontend never writes directly to sysfs. It never calls `sudo`. It never executes shell commands with `sh -c` for hardware control (only for the optional user-defined automation step).

---

## Feature Layer Stack

Every hardware feature follows the same six-layer stack:

```
View (ConsumerWidget)
  │  watches provider → renders state
  ▼
BLoC (Bloc<Event, State>)
  │  handles events, emits new states
  ▼
Repository
  │  translates between domain objects and raw I/O
  ▼
Snapshot (plain data class)
  │  raw poll result — no business logic
  ▼
Services (LegionSysfsService / LegionFrontendBridgeService)
  │  raw sysfs reads / pkexec writes
  ▼
Hardware (sysfs / legion_cli binary)
```

### Layer responsibilities

| Layer | Responsibility | Key rule |
|---|---|---|
| **View** | Render state; dispatch events on user action | Never reads sysfs directly; never calls the bridge directly |
| **BLoC** | Handle events; emit new `State`; coordinate repo calls | No I/O; no widget tree access |
| **Repository** | Fetch snapshots; call bridge for writes; translate exceptions | Single source of truth for domain logic |
| **Snapshot** | Immutable data bag returned by a single `loadSnapshot()` call | No methods beyond constructor |
| **Services** | `LegionSysfsService` (sysfs reads), `LegionFrontendBridgeService` (pkexec writes) | No domain knowledge |
| **Hardware** | sysfs nodes, `legion_cli` binary | External |

---

## Codebase Map

```
lib/
├── main.dart                          Entry point; mounts ProviderScope + App
├── app/
│   ├── app.dart                       Root widget
│   └── view/app.dart                  MaterialApp with Yaru theme
├── core/
│   ├── providers/
│   │   └── system_services_provider.dart   Riverpod providers for shared services
│   ├── services/
│   │   ├── legion_cli_service.dart         Process.run wrapper (pkexec or plain)
│   │   ├── legion_frontend_bridge_service.dart  Privileged command queue + error classification
│   │   ├── legion_sysfs_service.dart       Sysfs read helpers
│   │   └── xrandr_service.dart             Display resolution queries
│   └── widgets/
│       ├── app_shell_components.dart       AppPageBody, AppSectionCard, AppRefreshButton, …
│       └── privileged_action_notice.dart   PrivilegedActionNotice, confirmPrivilegedAction
└── features/
    ├── navigation/                    Sidebar nav, AppSection enum, NavigationShell
    ├── dashboard/                     Overview page (system status summary)
    ├── fans/                          Fan curve editor
    ├── power/                         Power mode, platform profile, power limits
    ├── battery_devices/               Battery conservation, rapid charging, always-on USB
    ├── boot_logo/                     Boot logo enable/restore/status
    ├── dgpu/                          Discrete GPU monitoring and deactivation
    ├── display_lighting/              LampArray / RGB lighting
    ├── automation/                    Profile-change automation with optional external command
    ├── settings/                      App settings, service control
    └── about/                         Diagnostics, version info

test/
├── features/<feature>/               Unit tests per feature
│   ├── <feature>_state_test.dart     State + copyWith tests
│   ├── <feature>_bloc_test.dart      BLoC handler tests (where present)
│   └── <feature>_model_test.dart     Model/parser tests (where present)
└── helpers/                          Shared test utilities (fakes, stubs)
```

Each feature directory follows the same internal layout:

```
features/<feature>/
├── bloc/
│   ├── <feature>_bloc.dart
│   ├── <feature>_event.dart
│   └── <feature>_state.dart
├── models/
│   ├── <feature>_snapshot.dart
│   └── <other models>.dart
├── repository/
│   └── <feature>_repository.dart
├── providers/
│   └── <feature>_provider.dart
└── view/
    └── <feature>_page.dart
```

---

## Data Flow: Read Path

How hardware state reaches the UI:

```
1. BLoC receives DashboardStarted (or <Feature>Started) event
2. BLoC emits state with isLoading: true
3. BLoC calls repository.loadSnapshot()
4. Repository reads sysfs files via LegionSysfsService
   (e.g. File('/sys/class/firmware-attributes/.../current_value').readAsString())
5. Repository builds <Feature>Snapshot from raw strings
6. Repository returns snapshot to BLoC
7. BLoC emits new State with snapshot fields, isLoading: false
8. Riverpod notifies ConsumerWidget → UI rebuilds
```

The snapshot is a one-shot poll result. It is not cached or stored — every refresh triggers a fresh `loadSnapshot()`.

### State equality and rebuild suppression

All `State` classes extend `Equatable`. BLoC only notifies listeners when the new state is not equal to the previous one. This means calling `loadSnapshot()` repeatedly when nothing changed produces no UI rebuilds — Equatable's `props` list determines what "equal" means.

All `Snapshot` classes also extend `Equatable` so that snapshots can be compared in tests without identity equality issues.

### Nullable fields and the `_unset` sentinel

Many state classes have nullable fields (e.g. `bool? isActive`, `String? errorMessage`). The `copyWith` method needs to distinguish between "caller wants to set this field to null" and "caller didn't pass this field at all (preserve current value)".

The sentinel pattern solves this:

```dart
static const _unset = Object();

DgpuState copyWith({
  Object? isActive = _unset,   // ← typed as Object? to accept both bool and _unset
  ...
}) {
  return DgpuState(
    isActive: isActive == _unset ? this.isActive : isActive as bool?,
    ...
  );
}
```

`_unset` is a private `Object` singleton. Because it is compared by identity (`==` on `Object` uses identity), it can never match any real value. This pattern appears in every state class in the codebase.

---

## Data Flow: Write Path (Privileged Commands)

How a user action (e.g. "set power mode to performance") reaches hardware:

```
1. User taps button in View
2. View calls confirmPrivilegedAction() — shows a confirmation dialog
3. User approves → View dispatches event (e.g. PowerModeChangeRequested)
4. BLoC receives event, emits isApplying: true
5. BLoC calls repository.setPowerMode('performance')
6. Repository calls bridgeService.runPrivilegedCommand(
     method: 'power.set_mode',
     args: ['set-feature', 'PlatformProfile', 'performance'],
     timeout: Duration(seconds: 5),
   )
7. BridgeService checks deduplication (same method+args already pending? → busy error)
8. BridgeService enqueues command in _privilegedQueue (sequential, never concurrent)
9. BridgeService calls LegionCliService.runCommand(args, privileged: true)
10. LegionCliService runs: pkexec /usr/bin/legion_cli set-feature PlatformProfile performance
    → polkit agent shows auth dialog (if not already authenticated)
    → kernel module writes to sysfs
11. Result returns up the chain; on success BLoC calls loadSnapshot() and emits updated state
12. On failure, BridgeService classifies the error code and throws LegionBridgeException
    → BLoC catches it, emits errorMessage
```

### Two write strategies

`legion_cli` supports two ways to write settings:

**Named subcommands** (feature-specific):
```
legion_cli set-feature PlatformProfile quiet
legion_cli batteryconservation-enable
legion_cli boot-logo enable /path/to/image.bmp
```

**Grouped subcommands** (for multi-step operations):
```
legion_cli boot-logo enable /path/to/image.bmp
legion_cli boot-logo restore
legion_cli dgpu kill-processes
legion_cli dgpu restart-pci
```

The choice between them is determined by what `legion_cli` exposes for each feature. See `docs/architecture/sysfs-vs-cli-access-audit.md` for the full feature-by-feature breakdown.

### Privileged command serialisation

The bridge service uses a future-chain queue (`_privilegedQueue`) to ensure privileged commands run one at a time. If a second write is requested while one is in flight, it either:
- Gets a `busy` error (if it's the exact same method+args — deduplication)
- Waits in the queue behind the first command (if it's a different command)

This prevents multiple polkit dialogs appearing simultaneously.

### Error classification

`LegionBridgeException` carries a `LegionBridgeErrorCode` classified by the bridge service from exit codes and output text:

| Code | Cause | UI message |
|---|---|---|
| `permissionDenied` | pkexec exit 126, polkit rejection, "authentication cancelled" | Approve the polkit prompt |
| `unavailable` | pkexec exit 127, "not supported", command not found | Verify legion_cli is installed |
| `busy` | Duplicate action in flight | Wait and retry |
| `timeout` | Command took longer than the timeout | Retry; check system load |
| `commandFailed` | Non-zero exit, unclassified | Shows stderr |

---

## Navigation and AppSection

All pages are registered in `lib/features/navigation/models/app_section.dart`. The `AppSection` enum is the single source of truth for:
- Which pages exist
- Sidebar label and icon
- Order in the navigation rail

Adding a new page requires:
1. Adding an entry to the `AppSection` enum
2. Adding `label`, `icon`, and `yaruIcon` switch cases
3. Adding a `case AppSection.<name>: return const <Name>Page();` in `NavigationShell._buildPage`
4. Adding the provider and bloc (see Contributing guide)

---

## State Management: Riverpod + riverbloc

The app uses **Riverpod** for dependency injection and **riverbloc** (a Riverpod adapter for flutter_bloc) for state management.

- `Provider<T>` — for services and repositories (no state, no disposal)
- `BlocProvider.autoDispose<B, S>` — for BLoC instances (disposed when the page leaves the screen)

All providers are defined in `lib/features/<feature>/providers/<feature>_provider.dart`.

The provider chain for every feature:
```dart
final <feature>RepositoryProvider = Provider<...>((ref) {
  final bridge = ref.watch(legionBridgeServiceProvider);
  return <Feature>Repository(bridgeService: bridge);
});

final <feature>BlocProvider = BlocProvider.autoDispose<...>((ref) {
  final repository = ref.watch(<feature>RepositoryProvider);
  return <Feature>Bloc(repository: repository)..add(const <Feature>Started());
});
```

In the View:
```dart
class <Feature>Page extends ConsumerWidget {
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(<feature>BlocProvider);
    final bloc = ref.read(<feature>BlocProvider.bloc);
    // ...
  }
}
```

---

## Testing Strategy

All tests are unit tests — no widget tests, no integration tests. Tests run without a connected device or kernel module.

**State tests** (`<feature>_state_test.dart`): verify `initial()` values, `copyWith` sentinel behaviour, `isAvailable`/computed getters, Equatable `props` equality.

**Model tests** (`<feature>_model_test.dart`): verify parsing logic (e.g. `DgpuProcess.parseNvidiaSmiOutput`, `FanCurve.fromSysfs`).

**BLoC tests** (`<feature>_bloc_test.dart`): use `mocktail` + `bloc_test` to verify handler sequences:
```dart
class FakeFansRepository extends Mock implements FansRepository {}

blocTest<FansBloc, FansState>(
  'emits loading then loaded on FansStarted',
  build: () => FansBloc(repository: mockRepo),
  act: (bloc) => bloc.add(const FansStarted()),
  expect: () => [isA<FansState>().having((s) => s.isLoading, 'isLoading', true), ...],
);
```

Run all tests:
```bash
flutter test
flutter analyze
```
