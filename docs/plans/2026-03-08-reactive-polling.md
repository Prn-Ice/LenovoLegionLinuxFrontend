# Reactive Polling Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add `Timer.periodic` background polling to five feature BLoCs so that state changes made outside the app (e.g. Fn-key power profile switch, AC plug/unplug) are reflected in the UI within ~5 seconds without user interaction.

**Architecture:** The `DashboardBloc` already contains the reference implementation of this pattern (`DashboardTicked` event, `_pollTimer`, `_started`, `_refreshInFlight`, `close()` override). This plan replicates that pattern verbatim across `FansBloc`, `PowerBloc`, `BatteryDevicesBloc`, `DisplayLightingBloc`, and `DgpuBloc`. No changes to repositories, providers, or views are required.

**Tech Stack:** `dart:async.Timer`; `riverbloc`; `bloc_test`; `mocktail`.

**Reference implementation:** `lib/features/dashboard/bloc/dashboard_bloc.dart` — read it before implementing any task.

---

### Task 1: FansBloc polling

**Files:**
- Modify: `lib/features/fans/bloc/fans_event.dart`
- Modify: `lib/features/fans/bloc/fans_bloc.dart`
- Modify: `test/features/fans/fans_bloc_test.dart`

**Step 1: Add `FansTicked` event**

In `fans_event.dart`, add after `FansRefreshRequested`:

```dart
final class FansTicked extends FansEvent {
  const FansTicked();
}
```

**Step 2: Update `FansBloc`**

Replace the entire `fans_bloc.dart` with:

```dart
import 'dart:async';

import 'package:riverbloc/riverbloc.dart';

import '../repository/fans_repository.dart';
import 'fans_event.dart';
import 'fans_state.dart';

class FansBloc extends Bloc<FansEvent, FansState> {
  FansBloc({
    required FansRepository repository,
    Duration pollInterval = const Duration(seconds: 5),
  }) : _repository = repository,
       _pollInterval = pollInterval,
       super(FansState.initial()) {
    on<FansStarted>(_onStarted);
    on<FansRefreshRequested>(_onRefreshRequested);
    on<FansTicked>(_onTicked);
    on<FansPresetSelectionChanged>(_onPresetSelectionChanged);
    on<FansApplyCurrentPresetRequested>(_onApplyCurrentPresetRequested);
    on<FansApplySelectedPresetRequested>(_onApplySelectedPresetRequested);
    on<MiniFanCurveSetRequested>(_onMiniFanCurveSetRequested);
    on<LockFanControllerSetRequested>(_onLockFanControllerSetRequested);
    on<MaximumFanSpeedSetRequested>(_onMaximumFanSpeedSetRequested);
    on<FanCurvePointUpdated>(_onFanCurvePointUpdated);
    on<FanCurveSaveRequested>(_onFanCurveSaveRequested);
  }

  final FansRepository _repository;
  final Duration _pollInterval;

  Timer? _pollTimer;
  bool _started = false;
  bool _refreshInFlight = false;

  Future<void> _onStarted(FansStarted event, Emitter<FansState> emit) async {
    if (_started) return;
    _started = true;
    await _reloadState(emit, showLoading: true);
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      add(const FansTicked());
    });
  }

  Future<void> _onRefreshRequested(
    FansRefreshRequested event,
    Emitter<FansState> emit,
  ) async {
    await _reloadState(emit, showLoading: true);
  }

  Future<void> _onTicked(FansTicked event, Emitter<FansState> emit) async {
    if (state.isApplying) return;
    await _reloadState(emit, showLoading: false);
  }

  void _onPresetSelectionChanged(
    FansPresetSelectionChanged event,
    Emitter<FansState> emit,
  ) {
    emit(state.copyWith(selectedPreset: event.preset, errorMessage: null));
  }

  Future<void> _onApplyCurrentPresetRequested(
    FansApplyCurrentPresetRequested event,
    Emitter<FansState> emit,
  ) async {
    await _apply(
      emit,
      action: _repository.applyCurrentContextPreset,
      successMessage: 'Applied current-context fan preset.',
    );
  }

  Future<void> _onApplySelectedPresetRequested(
    FansApplySelectedPresetRequested event,
    Emitter<FansState> emit,
  ) async {
    final selected = state.selectedPreset;
    if (selected == null || selected.isEmpty) {
      emit(
        state.copyWith(
          errorMessage: 'Select a preset before applying.',
          noticeMessage: null,
        ),
      );
      return;
    }

    await _apply(
      emit,
      action: () => _repository.applyPreset(selected),
      successMessage: 'Applied fan preset "$selected".',
    );
  }

  Future<void> _onMiniFanCurveSetRequested(
    MiniFanCurveSetRequested event,
    Emitter<FansState> emit,
  ) async {
    await _apply(
      emit,
      action: () => _repository.setMiniFanCurve(event.enabled),
      successMessage:
          'Mini fan curve ${event.enabled ? 'enabled' : 'disabled'}.',
    );
  }

  Future<void> _onLockFanControllerSetRequested(
    LockFanControllerSetRequested event,
    Emitter<FansState> emit,
  ) async {
    await _apply(
      emit,
      action: () => _repository.setLockFanController(event.enabled),
      successMessage:
          'Lock fan controller ${event.enabled ? 'enabled' : 'disabled'}.',
    );
  }

  Future<void> _onMaximumFanSpeedSetRequested(
    MaximumFanSpeedSetRequested event,
    Emitter<FansState> emit,
  ) async {
    await _apply(
      emit,
      action: () => _repository.setMaximumFanSpeed(event.enabled),
      successMessage:
          'Maximum fan speed ${event.enabled ? 'enabled' : 'disabled'}.',
    );
  }

  void _onFanCurvePointUpdated(
    FanCurvePointUpdated event,
    Emitter<FansState> emit,
  ) {
    final current = state.fanCurve;
    if (current == null || event.index < 0 || event.index >= 10) {
      return;
    }

    emit(
      state.copyWith(
        fanCurve: current.copyWithPoint(event.index, event.point),
        fanCurveDirty: true,
        errorMessage: null,
      ),
    );
  }

  Future<void> _onFanCurveSaveRequested(
    FanCurveSaveRequested event,
    Emitter<FansState> emit,
  ) async {
    final curve = state.fanCurve;
    if (curve == null || state.isApplying) {
      return;
    }

    emit(
      state.copyWith(isApplying: true, errorMessage: null, noticeMessage: null),
    );

    try {
      await _repository.writeFanCurveToHardware(curve);
      await _reloadState(emit, showLoading: false);
      emit(
        state.copyWith(
          isApplying: false,
          fanCurveDirty: false,
          noticeMessage: 'Fan curve applied to hardware.',
        ),
      );
    } catch (error) {
      emit(state.copyWith(isApplying: false, errorMessage: '$error'));
    }
  }

  Future<void> _apply(
    Emitter<FansState> emit, {
    required Future<void> Function() action,
    required String successMessage,
  }) async {
    if (state.isApplying) {
      return;
    }

    emit(
      state.copyWith(isApplying: true, errorMessage: null, noticeMessage: null),
    );

    try {
      await action();
      await _reloadState(emit, showLoading: false);
      emit(state.copyWith(isApplying: false, noticeMessage: successMessage));
    } catch (error) {
      emit(state.copyWith(isApplying: false, errorMessage: '$error'));
    }
  }

  Future<void> _reloadState(
    Emitter<FansState> emit, {
    required bool showLoading,
  }) async {
    if (_refreshInFlight) return;
    _refreshInFlight = true;

    if (showLoading) {
      emit(
        state.copyWith(
          isLoading: true,
          errorMessage: null,
          noticeMessage: null,
        ),
      );
    }

    try {
      final snapshot = await _repository.loadSnapshot();

      final selectedPreset = _resolveSelectedPreset(
        currentSelected: state.selectedPreset,
        recommendedPreset: snapshot.recommendedPreset,
        availablePresets: snapshot.availablePresets,
      );

      emit(
        state.copyWith(
          platformProfile: snapshot.platformProfile,
          onPowerSupply: snapshot.onPowerSupply,
          recommendedPreset: snapshot.recommendedPreset,
          availablePresets: snapshot.availablePresets,
          selectedPreset: selectedPreset,
          miniFanCurveEnabled: snapshot.miniFanCurveEnabled,
          lockFanControllerEnabled: snapshot.lockFanControllerEnabled,
          maximumFanSpeedEnabled: snapshot.maximumFanSpeedEnabled,
          fanCurve: state.fanCurveDirty ? state.fanCurve : snapshot.fanCurve,
          isLoading: false,
          errorMessage: null,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          isLoading: false,
          errorMessage: 'Failed to load fan settings: $error',
        ),
      );
    } finally {
      _refreshInFlight = false;
    }
  }

  String? _resolveSelectedPreset({
    required String? currentSelected,
    required String? recommendedPreset,
    required List<String> availablePresets,
  }) {
    if (currentSelected != null && availablePresets.contains(currentSelected)) {
      return currentSelected;
    }

    if (recommendedPreset != null &&
        availablePresets.contains(recommendedPreset)) {
      return recommendedPreset;
    }

    return availablePresets.isEmpty ? null : availablePresets.first;
  }

  @override
  Future<void> close() {
    _pollTimer?.cancel();
    return super.close();
  }
}
```

**Step 3: Add polling test to `fans_bloc_test.dart`**

Append these groups to the existing test file (after the last `group(...)`):

```dart
group('FansBloc FansTicked', () {
  late FakeFansRepository repo;

  setUp(() => repo = FakeFansRepository());

  blocTest<FansBloc, FansState>(
    'FansTicked reloads silently when not applying',
    build: () => FansBloc(repository: repo),
    seed: () => FansState.initial(),
    act: (bloc) => bloc.add(const FansTicked()),
    expect: () => [
      isA<FansState>().having((s) => s.isLoading, 'isLoading', false),
    ],
  );

  blocTest<FansBloc, FansState>(
    'FansTicked is skipped when isApplying',
    build: () => FansBloc(repository: repo),
    seed: () => FansState.initial().copyWith(isApplying: true),
    act: (bloc) => bloc.add(const FansTicked()),
    expect: () => isEmpty,
  );
});
```

**Step 4: Run tests**

```bash
flutter test test/features/fans/fans_bloc_test.dart
```

Expected: all tests PASS.

**Step 5: Commit**

```bash
git add lib/features/fans/bloc/fans_event.dart \
        lib/features/fans/bloc/fans_bloc.dart \
        test/features/fans/fans_bloc_test.dart
git commit -m "feat(fans): add FansTicked polling event with 5s background refresh"
```

---

### Task 2: PowerBloc polling

**Files:**
- Modify: `lib/features/power/bloc/power_event.dart`
- Modify: `lib/features/power/bloc/power_bloc.dart`
- Create: `test/features/power/power_bloc_test.dart`

**Step 1: Add `PowerTicked` event to `power_event.dart`**

Add after `PowerRefreshRequested`:

```dart
final class PowerTicked extends PowerEvent {
  const PowerTicked();
}
```

**Step 2: Update `PowerBloc`**

Add `import 'dart:async';` at the top. Add `pollInterval` param, fields, `_onTicked` handler, `_refreshInFlight` guard, and `close()` following the exact same pattern as `FansBloc` above.

Key changes from current code:

```dart
// Constructor:
PowerBloc({
  required PowerRepository repository,
  Duration pollInterval = const Duration(seconds: 5),
}) : _repository = repository,
     _pollInterval = pollInterval,
     super(PowerState.initial()) {
  on<PowerStarted>(_onStarted);
  on<PowerRefreshRequested>(_onRefreshRequested);
  on<PowerTicked>(_onTicked);           // ← add
  on<PowerModeSetRequested>(_onModeSetRequested);
  on<PowerLimitSetRequested>(_onLimitSetRequested);
  on<CpuOverclockSetRequested>(_onCpuOverclockSetRequested);
  on<GpuOverclockSetRequested>(_onGpuOverclockSetRequested);
}

final Duration _pollInterval;
Timer? _pollTimer;
bool _started = false;
bool _refreshInFlight = false;

// _onStarted:
Future<void> _onStarted(PowerStarted event, Emitter<PowerState> emit) async {
  if (_started) return;
  _started = true;
  await _reloadState(emit, showLoading: true);
  _pollTimer = Timer.periodic(_pollInterval, (_) {
    add(const PowerTicked());
  });
}

// _onTicked (new):
Future<void> _onTicked(PowerTicked event, Emitter<PowerState> emit) async {
  if (state.isApplying) return;
  await _reloadState(emit, showLoading: false);
}

// _reloadState: add guard at top and finally:
Future<void> _reloadState(Emitter<PowerState> emit, {required bool showLoading}) async {
  if (_refreshInFlight) return;
  _refreshInFlight = true;
  // ... existing body unchanged ...
  // add finally { _refreshInFlight = false; }
}

// close:
@override
Future<void> close() {
  _pollTimer?.cancel();
  return super.close();
}
```

**Step 3: Create `test/features/power/power_bloc_test.dart`**

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/power/bloc/power_bloc.dart';
import 'package:legion_frontend/features/power/bloc/power_event.dart';
import 'package:legion_frontend/features/power/bloc/power_state.dart';
import 'package:legion_frontend/features/power/repository/power_repository.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/fake_fans_repository.dart'; // for reference pattern only

class MockPowerRepository extends Mock implements PowerRepository {}

void main() {
  late MockPowerRepository repo;

  setUp(() {
    repo = MockPowerRepository();
    when(() => repo.loadSnapshot()).thenAnswer(
      (_) async => const PowerSnapshot(
        currentMode: null,
        availableModes: [],
        powerLimits: [],
        cpuOverclockEnabled: null,
        gpuOverclockEnabled: null,
      ),
    );
  });

  group('PowerBloc PowerTicked', () {
    blocTest<PowerBloc, PowerState>(
      'PowerTicked reloads silently when not applying',
      build: () => PowerBloc(repository: repo),
      seed: () => PowerState.initial(),
      act: (bloc) => bloc.add(const PowerTicked()),
      expect: () => [isA<PowerState>().having((s) => s.isLoading, 'isLoading', false)],
    );

    blocTest<PowerBloc, PowerState>(
      'PowerTicked is skipped when isApplying',
      build: () => PowerBloc(repository: repo),
      seed: () => PowerState.initial().copyWith(isApplying: true),
      act: (bloc) => bloc.add(const PowerTicked()),
      expect: () => isEmpty,
    );
  });
}
```

**Step 4: Run tests**

```bash
flutter test test/features/power/
```

Expected: all tests PASS.

**Step 5: Commit**

```bash
git add lib/features/power/bloc/power_event.dart \
        lib/features/power/bloc/power_bloc.dart \
        test/features/power/power_bloc_test.dart
git commit -m "feat(power): add PowerTicked polling event with 5s background refresh"
```

---

### Task 3: BatteryDevicesBloc polling

**Files:**
- Modify: `lib/features/battery_devices/bloc/battery_devices_event.dart`
- Modify: `lib/features/battery_devices/bloc/battery_devices_bloc.dart`
- Modify: `test/features/battery_devices/battery_devices_state_test.dart` (add bloc test to same dir, new file)

**Step 1: Add `BatteryDevicesTicked` event**

In `battery_devices_event.dart`, add after `BatteryDevicesRefreshRequested`:

```dart
final class BatteryDevicesTicked extends BatteryDevicesEvent {
  const BatteryDevicesTicked();
}
```

**Step 2: Update `BatteryDevicesBloc`**

Apply the same pattern: `import 'dart:async'`, `pollInterval` param, `_pollInterval`, `_pollTimer`, `_started`, `_refreshInFlight`, `_onTicked` handler, update `_onStarted`, add `_refreshInFlight` guard in `_reloadState`, override `close()`.

`_onTicked`:
```dart
Future<void> _onTicked(
  BatteryDevicesTicked event,
  Emitter<BatteryDevicesState> emit,
) async {
  if (state.isApplying) return;
  await _reloadState(emit, showLoading: false);
}
```

**Step 3: Create `test/features/battery_devices/battery_devices_bloc_test.dart`**

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/battery_devices/bloc/battery_devices_bloc.dart';
import 'package:legion_frontend/features/battery_devices/bloc/battery_devices_event.dart';
import 'package:legion_frontend/features/battery_devices/bloc/battery_devices_state.dart';
import 'package:legion_frontend/features/battery_devices/repository/battery_devices_repository.dart';
import 'package:mocktail/mocktail.dart';

class MockBatteryDevicesRepository extends Mock
    implements BatteryDevicesRepository {}

void main() {
  late MockBatteryDevicesRepository repo;

  setUp(() {
    repo = MockBatteryDevicesRepository();
    when(() => repo.loadSnapshot()).thenAnswer(
      (_) async => const BatteryDevicesSnapshot(
        batteryConservationEnabled: null,
        rapidChargingEnabled: null,
        alwaysOnUsbChargingEnabled: null,
        alwaysOnUsbWriteSupported: false,
        touchpadEnabled: null,
        winKeyEnabled: null,
        cameraPowerEnabled: null,
        fnLockEnabled: null,
      ),
    );
  });

  group('BatteryDevicesBloc BatteryDevicesTicked', () {
    blocTest<BatteryDevicesBloc, BatteryDevicesState>(
      'BatteryDevicesTicked reloads silently when not applying',
      build: () => BatteryDevicesBloc(repository: repo),
      seed: () => BatteryDevicesState.initial(),
      act: (bloc) => bloc.add(const BatteryDevicesTicked()),
      expect: () => [
        isA<BatteryDevicesState>().having((s) => s.isLoading, 'isLoading', false),
      ],
    );

    blocTest<BatteryDevicesBloc, BatteryDevicesState>(
      'BatteryDevicesTicked is skipped when isApplying',
      build: () => BatteryDevicesBloc(repository: repo),
      seed: () => BatteryDevicesState.initial().copyWith(isApplying: true),
      act: (bloc) => bloc.add(const BatteryDevicesTicked()),
      expect: () => isEmpty,
    );
  });
}
```

> **Note:** Check `BatteryDevicesSnapshot`'s actual constructor fields by reading `lib/features/battery_devices/models/battery_devices_snapshot.dart` before writing the test — adjust the `thenAnswer` accordingly.

**Step 4: Run tests**

```bash
flutter test test/features/battery_devices/
```

Expected: all tests PASS.

**Step 5: Commit**

```bash
git add lib/features/battery_devices/bloc/battery_devices_event.dart \
        lib/features/battery_devices/bloc/battery_devices_bloc.dart \
        test/features/battery_devices/battery_devices_bloc_test.dart
git commit -m "feat(battery_devices): add BatteryDevicesTicked polling event with 5s background refresh"
```

---

### Task 4: DisplayLightingBloc polling

**Files:**
- Modify: `lib/features/display_lighting/bloc/display_lighting_event.dart`
- Modify: `lib/features/display_lighting/bloc/display_lighting_bloc.dart`
- Create: `test/features/display_lighting/display_lighting_bloc_test.dart`

**Step 1: Add `DisplayLightingTicked` event**

```dart
final class DisplayLightingTicked extends DisplayLightingEvent {
  const DisplayLightingTicked();
}
```

**Step 2: Update `DisplayLightingBloc`**

Apply the same pattern. `_onTicked`:

```dart
Future<void> _onTicked(
  DisplayLightingTicked event,
  Emitter<DisplayLightingState> emit,
) async {
  if (state.isApplying) return;
  await _reloadState(emit, showLoading: false);
}
```

**Step 3: Create `test/features/display_lighting/display_lighting_bloc_test.dart`**

Same structure as the battery devices test above — mock repository, `loadSnapshot` returns an empty snapshot, verify `DisplayLightingTicked` skips when applying and reloads silently otherwise.

> Read `lib/features/display_lighting/models/display_lighting_snapshot.dart` to find the correct constructor fields for the mock snapshot.

**Step 4: Run tests**

```bash
flutter test test/features/display_lighting/
```

**Step 5: Commit**

```bash
git add lib/features/display_lighting/bloc/display_lighting_event.dart \
        lib/features/display_lighting/bloc/display_lighting_bloc.dart \
        test/features/display_lighting/display_lighting_bloc_test.dart
git commit -m "feat(display_lighting): add DisplayLightingTicked polling event with 5s background refresh"
```

---

### Task 5: DgpuBloc polling

**Files:**
- Modify: `lib/features/dgpu/bloc/dgpu_event.dart`
- Modify: `lib/features/dgpu/bloc/dgpu_bloc.dart`
- Modify: `test/features/dgpu/dgpu_bloc_test.dart` (create if missing)

**Step 1: Add `DgpuTicked` event to `dgpu_event.dart`**

```dart
final class DgpuTicked extends DgpuEvent {
  const DgpuTicked();
}
```

**Step 2: Update `DgpuBloc`**

`DgpuBloc._reloadState` does not have a `showLoading` parameter currently. Add one with default `false` and guard with `_refreshInFlight`. Apply the same timer pattern.

Updated `_reloadState` signature:
```dart
Future<void> _reloadState(
  Emitter<DgpuState> emit, {
  String? noticeMessage,
  bool showLoading = false,
}) async {
  if (_refreshInFlight) return;
  _refreshInFlight = true;
  if (showLoading) {
    emit(state.copyWith(isLoading: true, errorMessage: null));
  }
  try {
    // ... existing body ...
  } finally {
    _refreshInFlight = false;
  }
}
```

Update all existing call sites:
- `_onStarted`: `_reloadState(emit, showLoading: true)` (already sets `isLoading: true` before call — remove the manual emit, or keep it and pass `showLoading: false`)
- `_onRefreshRequested`: `_reloadState(emit)`
- `_onKillProcessesRequested`: `_reloadState(emit, noticeMessage: '...')`
- `_onRestartPciRequested`: `_reloadState(emit, noticeMessage: '...')`

`_onTicked`:
```dart
Future<void> _onTicked(DgpuTicked event, Emitter<DgpuState> emit) async {
  if (state.isApplying) return;
  await _reloadState(emit);
}
```

`_onStarted`:
```dart
Future<void> _onStarted(DgpuStarted event, Emitter<DgpuState> emit) async {
  if (_started) return;
  _started = true;
  emit(state.copyWith(isLoading: true, errorMessage: null));
  await _reloadState(emit);
  _pollTimer = Timer.periodic(_pollInterval, (_) {
    add(const DgpuTicked());
  });
}
```

**Step 3: Add polling tests**

```dart
group('DgpuBloc DgpuTicked', () {
  blocTest<DgpuBloc, DgpuState>(
    'DgpuTicked reloads silently when not applying',
    build: () => DgpuBloc(repository: mockRepo),
    seed: () => DgpuState.initial(),
    act: (bloc) => bloc.add(const DgpuTicked()),
    expect: () => [isA<DgpuState>().having((s) => s.isLoading, 'isLoading', false)],
  );

  blocTest<DgpuBloc, DgpuState>(
    'DgpuTicked is skipped when isApplying',
    build: () => DgpuBloc(repository: mockRepo),
    seed: () => DgpuState.initial().copyWith(isApplying: true),
    act: (bloc) => bloc.add(const DgpuTicked()),
    expect: () => isEmpty,
  );
});
```

**Step 4: Run tests**

```bash
flutter test test/features/dgpu/
```

**Step 5: Commit**

```bash
git add lib/features/dgpu/bloc/dgpu_event.dart \
        lib/features/dgpu/bloc/dgpu_bloc.dart \
        test/features/dgpu/
git commit -m "feat(dgpu): add DgpuTicked polling event with 5s background refresh"
```

---

### Task 6: Final verification and close

**Step 1: Full test suite**

```bash
flutter test --reporter=expanded
```

Expected: all tests PASS.

**Step 2: Static analysis**

```bash
flutter analyze
```

Expected: No issues found.

**Step 3: Close the bead**

```bash
cd /home/prnice/Projects/personal/LenovoLegionLinux
bd close LenovoLegionLinux-okf.18 \
  --reason "Implemented timer-based polling (5s) on FansBloc, PowerBloc, BatteryDevicesBloc, DisplayLightingBloc, DgpuBloc — replicating the DashboardBloc pattern. inotify and legion_cli monitor were ruled out (see dnd comment). Dashboard already had polling at 3s."
```
