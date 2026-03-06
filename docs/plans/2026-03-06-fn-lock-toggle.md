# Fn-Lock Toggle Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a Fn-lock toggle to the Battery & Devices page → Input Devices section.

**Architecture:** The fn-lock sysfs file lives at `/sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/fn_lock` (same ideapad_acpi driver as battery conservation and camera power). Reads go via `LegionSysfsService`; writes go via `LegionFrontendBridgeService` calling the `fnlock-enable`/`fnlock-disable` CLI subcommands. The toggle plugs into the existing BatteryDevices BLoC following the winkey/touchpad pattern exactly — touching 6 layers in the same order.

**Tech Stack:** Dart/Flutter, riverbloc (flutter_bloc wrapper), flutter_riverpod, flutter_test, Yaru widgets.

**Bead:** LenovoLegionLinux-p03

---

## Layer Map (read this before starting)

Every boolean toggle in this feature follows a fixed 6-layer chain:

```
sysfs service (read)
  → snapshot (DTO)
    → state (BLoC state)
      → event (BLoC event)
        → repository (read + write)
          → bloc (handler)
            → UI (AppSwitchTile)
```

Each task below corresponds to one or two layers. Do them in order.

---

## Task 1: Write failing state unit tests

Write the tests first so they fail, then make them pass in Task 2.

**Files:**
- Create: `test/features/battery_devices/battery_devices_state_test.dart`

**Step 1: Create test directory**

```bash
mkdir -p test/features/battery_devices
```

**Step 2: Write the failing tests**

```dart
// test/features/battery_devices/battery_devices_state_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/battery_devices/bloc/battery_devices_state.dart';

void main() {
  group('BatteryDevicesState fnLock', () {
    test('initial state has fnLockEnabled as null', () {
      final state = BatteryDevicesState.initial();
      expect(state.fnLockEnabled, isNull);
    });

    test('copyWith fnLockEnabled: true sets it', () {
      final state = BatteryDevicesState.initial().copyWith(fnLockEnabled: true);
      expect(state.fnLockEnabled, isTrue);
    });

    test('copyWith fnLockEnabled: null preserves null', () {
      final state = BatteryDevicesState.initial();
      // copyWith with no fnLockEnabled arg must not change it
      final updated = state.copyWith(isLoading: false);
      expect(updated.fnLockEnabled, isNull);
    });

    test('hasLoaded is true when only fnLockEnabled is set', () {
      final state = BatteryDevicesState.initial().copyWith(fnLockEnabled: false);
      expect(state.hasLoaded, isTrue);
    });

    test('props distinguishes fnLockEnabled true vs false', () {
      final s1 = BatteryDevicesState.initial().copyWith(fnLockEnabled: true);
      final s2 = BatteryDevicesState.initial().copyWith(fnLockEnabled: false);
      expect(s1, isNot(equals(s2)));
    });
  });
}
```

**Step 3: Run to confirm failure**

```bash
cd frontend/legion_frontend && flutter test test/features/battery_devices/battery_devices_state_test.dart
```

Expected: FAIL — `The getter 'fnLockEnabled' isn't defined for the type 'BatteryDevicesState'`

---

## Task 2: Add fnLockEnabled to snapshot, state, and event

**Files:**
- Modify: `lib/features/battery_devices/models/battery_devices_snapshot.dart`
- Modify: `lib/features/battery_devices/bloc/battery_devices_state.dart`
- Modify: `lib/features/battery_devices/bloc/battery_devices_event.dart`

### Step 1: Update snapshot

Replace the entire file content of `battery_devices_snapshot.dart` with:

```dart
class BatteryDevicesSnapshot {
  const BatteryDevicesSnapshot({
    required this.batteryConservationEnabled,
    required this.rapidChargingEnabled,
    required this.alwaysOnUsbChargingEnabled,
    required this.alwaysOnUsbWriteSupported,
    required this.touchpadEnabled,
    required this.winKeyEnabled,
    required this.cameraPowerEnabled,
    required this.fnLockEnabled,
  });

  final bool? batteryConservationEnabled;
  final bool? rapidChargingEnabled;
  final bool? alwaysOnUsbChargingEnabled;
  final bool alwaysOnUsbWriteSupported;
  final bool? touchpadEnabled;
  final bool? winKeyEnabled;
  final bool? cameraPowerEnabled;
  final bool? fnLockEnabled;
}
```

### Step 2: Update state

In `battery_devices_state.dart`, make these changes (5 locations):

**a) Constructor parameter** — after `cameraPowerEnabled`:
```dart
required this.fnLockEnabled,
```

**b) Field declaration** — after `final bool? cameraPowerEnabled;`:
```dart
final bool? fnLockEnabled;
```

**c) `initial()` factory** — after `cameraPowerEnabled: null,`:
```dart
fnLockEnabled: null,
```

**d) `hasLoaded` getter** — add to the OR chain:
```dart
bool get hasLoaded =>
    batteryConservationEnabled != null ||
    rapidChargingEnabled != null ||
    alwaysOnUsbChargingEnabled != null ||
    touchpadEnabled != null ||
    winKeyEnabled != null ||
    cameraPowerEnabled != null ||
    fnLockEnabled != null;
```

**e) `copyWith` signature** — after `Object? cameraPowerEnabled = _unset,`:
```dart
Object? fnLockEnabled = _unset,
```

**f) `copyWith` body** — after the `cameraPowerEnabled:` line:
```dart
fnLockEnabled: fnLockEnabled == _unset
    ? this.fnLockEnabled
    : fnLockEnabled as bool?,
```

**g) `props` list** — after `cameraPowerEnabled,`:
```dart
fnLockEnabled,
```

### Step 3: Add FnLockSetRequested event

At the end of `battery_devices_event.dart`, add:

```dart
final class FnLockSetRequested extends BatteryDevicesEvent {
  const FnLockSetRequested(this.enabled);

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}
```

### Step 4: Run the state tests — they should now pass

```bash
cd frontend/legion_frontend && flutter test test/features/battery_devices/battery_devices_state_test.dart
```

Expected: PASS (5 tests)

### Step 5: Run analyze to catch any missed spots

```bash
cd frontend/legion_frontend && flutter analyze lib/features/battery_devices/
```

Expected: no issues (if snapshot's new required field causes errors elsewhere, fix them in Task 4)

### Step 6: Commit

```bash
cd frontend/legion_frontend
git add lib/features/battery_devices/models/battery_devices_snapshot.dart \
        lib/features/battery_devices/bloc/battery_devices_state.dart \
        lib/features/battery_devices/bloc/battery_devices_event.dart \
        test/features/battery_devices/battery_devices_state_test.dart
git commit -m "feat(battery-devices): add fnLock fields to snapshot, state, and event"
```

---

## Task 3: Add readFnLockMode to sysfs service

**Files:**
- Modify: `lib/core/services/legion_sysfs_service.dart`

### Step 1: Add path constant

After the `_cameraPowerPath` constant (line ~28), add:

```dart
static const String _fnLockPath =
    '/sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/fn_lock';
```

### Step 2: Add read method

After `readCameraPowerMode()`, add:

```dart
Future<bool?> readFnLockMode() async {
  return _readBoolFile(_fnLockPath);
}
```

### Step 3: Analyze

```bash
cd frontend/legion_frontend && flutter analyze lib/core/services/legion_sysfs_service.dart
```

Expected: no issues

### Step 4: Commit

```bash
cd frontend/legion_frontend
git add lib/core/services/legion_sysfs_service.dart
git commit -m "feat(sysfs): add readFnLockMode — reads ideapad_acpi fn_lock node"
```

---

## Task 4: Wire fn-lock in repository (read + write)

**Files:**
- Modify: `lib/features/battery_devices/repository/battery_devices_repository.dart`

### Step 1: Add fn-lock read to loadSnapshot

In `loadSnapshot()`, after the `cameraPower` read line, add:

```dart
final fnLock = await _sysfsService.readFnLockMode();
```

In the `BatteryDevicesSnapshot(...)` constructor call, after `cameraPowerEnabled: cameraPower,`, add:

```dart
fnLockEnabled: fnLock,
```

### Step 2: Add setFnLock write method

After `setWinKey()`, add:

```dart
Future<void> setFnLock(bool enabled) async {
  final command = enabled ? 'fnlock-enable' : 'fnlock-disable';
  await _runPrivilegedCommand(
    [command],
    method: 'fn_lock.set',
    failurePrefix: 'Failed to set Fn lock to ${enabled ? 'on' : 'off'}',
  );
}
```

### Step 3: Analyze

```bash
cd frontend/legion_frontend && flutter analyze lib/features/battery_devices/repository/battery_devices_repository.dart
```

Expected: no issues

### Step 4: Commit

```bash
cd frontend/legion_frontend
git add lib/features/battery_devices/repository/battery_devices_repository.dart
git commit -m "feat(battery-devices): wire fn-lock read/write in BatteryDevicesRepository"
```

---

## Task 5: Add FnLock handler to bloc

**Files:**
- Modify: `lib/features/battery_devices/bloc/battery_devices_bloc.dart`

### Step 1: Register handler in constructor

After `on<WinKeySetRequested>(_onWinKeySetRequested);`, add:

```dart
on<FnLockSetRequested>(_onFnLockSetRequested);
```

### Step 2: Add handler method

After `_onWinKeySetRequested(...)`, add:

```dart
Future<void> _onFnLockSetRequested(
  FnLockSetRequested event,
  Emitter<BatteryDevicesState> emit,
) async {
  await _apply(
    emit,
    action: () => _repository.setFnLock(event.enabled),
    successMessage: 'Fn lock ${event.enabled ? 'enabled' : 'disabled'}.',
  );
}
```

### Step 3: Wire fnLockEnabled in _reloadState

In `_reloadState`, inside the `state.copyWith(...)` call after `cameraPowerEnabled: snapshot.cameraPowerEnabled,`, add:

```dart
fnLockEnabled: snapshot.fnLockEnabled,
```

### Step 4: Analyze

```bash
cd frontend/legion_frontend && flutter analyze lib/features/battery_devices/bloc/battery_devices_bloc.dart
```

Expected: no issues

### Step 5: Commit

```bash
cd frontend/legion_frontend
git add lib/features/battery_devices/bloc/battery_devices_bloc.dart
git commit -m "feat(battery-devices): add FnLockSetRequested handler in BatteryDevicesBloc"
```

---

## Task 6: Add fn-lock toggle to the UI

**Files:**
- Modify: `lib/features/battery_devices/view/battery_devices_page.dart`

### Step 1: Add AppSwitchTile for fn-lock

In the Input Devices `AppSectionCard`, after the Win key `AppSwitchTile` block (the one ending with `title: 'Win key', subtitle: boolEnabledLabel(state.winKeyEnabled),`) and before the Camera power `ListTile`, insert:

```dart
AppSwitchTile(
  value: state.fnLockEnabled ?? false,
  onChanged: _isWritable(state.fnLockEnabled, state.isApplying)
      ? (enabled) async {
          final confirmed = await confirmPrivilegedAction(
            context,
            title: 'Set Fn lock',
            message:
                'This action uses privileged access and may prompt for authentication.',
            confirmLabel: 'Apply',
          );
          if (!context.mounted || !confirmed) {
            return;
          }
          bloc.add(FnLockSetRequested(enabled));
        }
      : null,
  title: 'Fn lock',
  subtitle: boolEnabledLabel(state.fnLockEnabled),
),
```

No new imports needed — `FnLockSetRequested` is already covered by the existing `import '../bloc/battery_devices_event.dart';`.

### Step 2: Run all tests

```bash
cd frontend/legion_frontend && flutter test
```

Expected: PASS (all tests including the 5 new state tests)

### Step 3: Run full analyze

```bash
cd frontend/legion_frontend && flutter analyze
```

Expected: no issues

### Step 4: Commit

```bash
cd frontend/legion_frontend
git add lib/features/battery_devices/view/battery_devices_page.dart
git commit -m "feat(battery-devices): add Fn lock toggle to Input Devices section

Closes LenovoLegionLinux-p03"
```

---

## Verification Checklist

Before declaring done:

- [ ] `flutter test` — all tests pass
- [ ] `flutter analyze` — zero issues
- [ ] The 5 state tests in `test/features/battery_devices/battery_devices_state_test.dart` all pass
- [ ] `BatteryDevicesState.initial().fnLockEnabled` is `null`
- [ ] `BatteryDevicesState.initial().hasLoaded` is `false` (fn-lock alone doesn't flip it until a value arrives)
- [ ] Fn lock toggle appears between Win key and Camera power in the Input Devices section
- [ ] Toggle is disabled (grayed) when fn-lock sysfs file is unavailable on the device (`fnLockEnabled == null`)
