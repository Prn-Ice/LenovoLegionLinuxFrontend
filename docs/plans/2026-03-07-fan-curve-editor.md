# Fan Curve Editor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a Fan Curve section to the Fans page with a 10-point table editor showing CPU/GPU temperature thresholds and fan RPM per point, with Apply-to-hardware support.

**Architecture:** Reads the fan curve from sysfs hwmon files (PWM → RPM conversion) using an extended `LegionSysfsService`. Writes via serialising the curve to YAML → writing to `/tmp/legion_frontend_custom_curve.yaml` (unprivileged) → calling `pkexec legion_cli fancurve-write-file-to-hw <path>` via `FansRepository`. Python's `fancurve_write_file_to_hw` does the RPM→PWM conversion and writes to hwmon. The UI uses a `ConsumerStatefulWidget` table with one row per point and `TextFormField` cells for CPU/GPU temps and fan RPMs; IC temps and accel/decel are preserved read-write but not displayed.

**Tech Stack:** Dart/Flutter, riverbloc, flutter_riverpod, flutter_test, Yaru widgets, `dart:io`.

**Bead:** LenovoLegionLinux-s21

**IMPORTANT — direnv:** Always `cd` to the repo root or `frontend/legion_frontend` before running Flutter commands so direnv activates Flutter from the Nix flake.

---

## Data structures (read this before starting)

**Python `FanCurveEntry` fields** (10 per curve):
| Field | Type | sysfs file | Note |
|---|---|---|---|
| `fan1_speed` | float (RPM) | `pwm1_auto_point{N}_pwm` | stored as PWM 0-255 |
| `fan2_speed` | float (RPM) | `pwm2_auto_point{N}_pwm` | stored as PWM 0-255 |
| `cpu_lower_temp` | int (°C) | `pwm1_auto_point{N}_temp_hyst` | hysteresis lower |
| `cpu_upper_temp` | int (°C) | `pwm1_auto_point{N}_temp` | trigger upper |
| `gpu_lower_temp` | int (°C) | `pwm2_auto_point{N}_temp_hyst` | |
| `gpu_upper_temp` | int (°C) | `pwm2_auto_point{N}_temp` | |
| `ic_lower_temp` | int (°C) | `pwm3_auto_point{N}_temp_hyst` | preserved, not editable in UI |
| `ic_upper_temp` | int (°C) | `pwm3_auto_point{N}_temp` | preserved, not editable in UI |
| `acceleration` | int | `pwm1_auto_point{N}_accel` | preserved, not editable in UI |
| `deceleration` | int | `pwm1_auto_point{N}_decel` | preserved, not editable in UI |

Point indices are 1-10 in sysfs. `fan1_max` and `fan2_max` files give max RPM for PWM→RPM conversion.

**hwmon base path:** `/sys/module/legion_laptop/drivers/platform:legion/PNP0C09:00/hwmon`
**hwmon subdirectory pattern:** `hwmon*/` (found by listing the base path)

**PWM ↔ RPM conversion:**
- Read: `rpm = (pwm / 255.0 * max_rpm).round()`
- Write: not needed in Dart — Python does it from the YAML RPM values

**YAML format** (must match Python's `FanCurve.from_yaml`):
```yaml
name: custom
entries:
- fan1_speed: 1200.0
  fan2_speed: 1200.0
  cpu_lower_temp: 40
  cpu_upper_temp: 50
  gpu_lower_temp: 40
  gpu_upper_temp: 50
  ic_lower_temp: 40
  ic_upper_temp: 50
  acceleration: 2
  deceleration: 2
- ...
enable_minifancurve: true
```

**Layer map:**
```
FanCurve model (new — lib/features/fans/models/fan_curve.dart)
  → LegionSysfsService (new readFanCurve method)
    → FansSnapshot (new fanCurve + fan max RPM fields)
      → FansState (new fanCurve + fanCurveDirty + max RPM fields)
        → FansEvent (new FanCurvePointUpdated + FanCurveSaveRequested)
          → FansRepository (new writeFanCurveToHardware)
            → FansBloc (new handlers + _reloadState wiring)
              → FansPage (new Fan Curve section)
```

---

## Task 1: Write failing model unit tests

**Files:**
- Create: `test/features/fans/fan_curve_test.dart`
- Create: `test/features/fans/` directory

### Step 1: Create test directory

```bash
cd frontend/legion_frontend
mkdir -p test/features/fans
```

### Step 2: Write the failing tests

```dart
// test/features/fans/fan_curve_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/fans/models/fan_curve.dart';

FanCurvePoint _makePoint({
  int fan1Rpm = 1000,
  int fan2Rpm = 1000,
  int cpuLower = 40,
  int cpuUpper = 50,
  int gpuLower = 40,
  int gpuUpper = 50,
  int icLower = 40,
  int icUpper = 50,
  int accel = 2,
  int decel = 2,
}) =>
    FanCurvePoint(
      fan1Rpm: fan1Rpm,
      fan2Rpm: fan2Rpm,
      cpuLowerTemp: cpuLower,
      cpuUpperTemp: cpuUpper,
      gpuLowerTemp: gpuLower,
      gpuUpperTemp: gpuUpper,
      icLowerTemp: icLower,
      icUpperTemp: icUpper,
      accel: accel,
      decel: decel,
    );

void main() {
  group('FanCurvePoint', () {
    test('copyWith changes only the specified field', () {
      final p = _makePoint(fan1Rpm: 1000, cpuUpperTemp: 50);
      final p2 = p.copyWith(fan1Rpm: 2000);
      expect(p2.fan1Rpm, equals(2000));
      expect(p2.cpuUpperTemp, equals(50)); // unchanged
    });

    test('equality holds for identical instances', () {
      final p1 = _makePoint();
      final p2 = _makePoint();
      expect(p1, equals(p2));
    });
  });

  group('FanCurve', () {
    late List<FanCurvePoint> tenPoints;

    setUp(() {
      tenPoints = List.generate(10, (_) => _makePoint());
    });

    test('has exactly 10 points', () {
      final curve = FanCurve(name: 'test', points: tenPoints);
      expect(curve.points.length, equals(10));
    });

    test('copyWith replaces a point at index', () {
      final curve = FanCurve(name: 'test', points: tenPoints);
      final updated = _makePoint(fan1Rpm: 3000);
      final curve2 = curve.copyWithPoint(2, updated);
      expect(curve2.points[2].fan1Rpm, equals(3000));
      expect(curve2.points[0].fan1Rpm, equals(1000)); // unchanged
    });

    test('toYaml produces parseable output with correct fields', () {
      final curve = FanCurve(
        name: 'custom',
        points: tenPoints,
        enableMiniFanCurve: true,
      );
      final yaml = curve.toYaml();
      expect(yaml, contains('name: custom'));
      expect(yaml, contains('enable_minifancurve: true'));
      expect(yaml, contains('fan1_speed: 1000.0'));
      expect(yaml, contains('cpu_lower_temp: 40'));
      expect(yaml, contains('acceleration: 2'));
    });

    test('toYaml contains exactly 10 entries', () {
      final curve = FanCurve(name: 'custom', points: tenPoints);
      final yaml = curve.toYaml();
      // Each entry starts with '- fan1_speed'
      final entryCount =
          RegExp(r'- fan1_speed').allMatches(yaml).length;
      expect(entryCount, equals(10));
    });
  });
}
```

### Step 3: Run to confirm failure

```bash
cd frontend/legion_frontend
flutter test test/features/fans/fan_curve_test.dart
```

Expected: FAIL — `'fan_curve.dart' not found`

---

## Task 2: Create the FanCurve model

**Files:**
- Create: `lib/features/fans/models/fan_curve.dart`

### Step 1: Create the file

```dart
// lib/features/fans/models/fan_curve.dart
import 'package:equatable/equatable.dart';

class FanCurvePoint extends Equatable {
  const FanCurvePoint({
    required this.fan1Rpm,
    required this.fan2Rpm,
    required this.cpuLowerTemp,
    required this.cpuUpperTemp,
    required this.gpuLowerTemp,
    required this.gpuUpperTemp,
    required this.icLowerTemp,
    required this.icUpperTemp,
    required this.accel,
    required this.decel,
  });

  final int fan1Rpm;
  final int fan2Rpm;
  final int cpuLowerTemp;
  final int cpuUpperTemp;
  final int gpuLowerTemp;
  final int gpuUpperTemp;
  final int icLowerTemp;
  final int icUpperTemp;
  final int accel;
  final int decel;

  FanCurvePoint copyWith({
    int? fan1Rpm,
    int? fan2Rpm,
    int? cpuLowerTemp,
    int? cpuUpperTemp,
    int? gpuLowerTemp,
    int? gpuUpperTemp,
    int? icLowerTemp,
    int? icUpperTemp,
    int? accel,
    int? decel,
  }) {
    return FanCurvePoint(
      fan1Rpm: fan1Rpm ?? this.fan1Rpm,
      fan2Rpm: fan2Rpm ?? this.fan2Rpm,
      cpuLowerTemp: cpuLowerTemp ?? this.cpuLowerTemp,
      cpuUpperTemp: cpuUpperTemp ?? this.cpuUpperTemp,
      gpuLowerTemp: gpuLowerTemp ?? this.gpuLowerTemp,
      gpuUpperTemp: gpuUpperTemp ?? this.gpuUpperTemp,
      icLowerTemp: icLowerTemp ?? this.icLowerTemp,
      icUpperTemp: icUpperTemp ?? this.icUpperTemp,
      accel: accel ?? this.accel,
      decel: decel ?? this.decel,
    );
  }

  @override
  List<Object?> get props => [
    fan1Rpm,
    fan2Rpm,
    cpuLowerTemp,
    cpuUpperTemp,
    gpuLowerTemp,
    gpuUpperTemp,
    icLowerTemp,
    icUpperTemp,
    accel,
    decel,
  ];
}

class FanCurve extends Equatable {
  const FanCurve({
    required this.name,
    required this.points,
    this.enableMiniFanCurve = true,
  });

  final String name;

  /// Always 10 points (indexed 0-9, map to hardware points 1-10).
  final List<FanCurvePoint> points;
  final bool enableMiniFanCurve;

  /// Returns a new [FanCurve] with [point] replacing the entry at [index].
  FanCurve copyWithPoint(int index, FanCurvePoint point) {
    final updated = List<FanCurvePoint>.from(points);
    updated[index] = point;
    return FanCurve(
      name: name,
      points: List.unmodifiable(updated),
      enableMiniFanCurve: enableMiniFanCurve,
    );
  }

  FanCurve copyWith({
    String? name,
    List<FanCurvePoint>? points,
    bool? enableMiniFanCurve,
  }) {
    return FanCurve(
      name: name ?? this.name,
      points: points ?? this.points,
      enableMiniFanCurve: enableMiniFanCurve ?? this.enableMiniFanCurve,
    );
  }

  /// Serialises to YAML compatible with Python's FanCurve.from_yaml().
  String toYaml() {
    final buf = StringBuffer();
    buf.writeln('name: $name');
    buf.writeln('entries:');
    for (final p in points) {
      buf.writeln('- fan1_speed: ${p.fan1Rpm}.0');
      buf.writeln('  fan2_speed: ${p.fan2Rpm}.0');
      buf.writeln('  cpu_lower_temp: ${p.cpuLowerTemp}');
      buf.writeln('  cpu_upper_temp: ${p.cpuUpperTemp}');
      buf.writeln('  gpu_lower_temp: ${p.gpuLowerTemp}');
      buf.writeln('  gpu_upper_temp: ${p.gpuUpperTemp}');
      buf.writeln('  ic_lower_temp: ${p.icLowerTemp}');
      buf.writeln('  ic_upper_temp: ${p.icUpperTemp}');
      buf.writeln('  acceleration: ${p.accel}');
      buf.writeln('  deceleration: ${p.decel}');
    }
    buf.writeln(
      'enable_minifancurve: ${enableMiniFanCurve ? 'true' : 'false'}',
    );
    return buf.toString();
  }

  @override
  List<Object?> get props => [name, points, enableMiniFanCurve];
}
```

### Step 2: Run the model tests — they should now pass

```bash
cd frontend/legion_frontend
flutter test test/features/fans/fan_curve_test.dart
```

Expected: PASS (6 tests)

### Step 3: Analyze

```bash
cd frontend/legion_frontend
flutter analyze lib/features/fans/models/fan_curve.dart
```

Expected: no issues

### Step 4: Commit

```bash
cd frontend/legion_frontend
git add lib/features/fans/models/fan_curve.dart \
        test/features/fans/fan_curve_test.dart
git commit -m "feat(fans): add FanCurvePoint + FanCurve model with toYaml serialisation"
```

---

## Task 3: Add readFanCurve to LegionSysfsService

**Files:**
- Modify: `lib/core/services/legion_sysfs_service.dart`

### Step 1: Add the import at the top

```dart
import '../../features/fans/models/fan_curve.dart';
```

### Step 2: Extract _findFanHwmonDir helper

The existing `readMiniFanCurveMode()` method manually walks the hwmon directory. Extract that logic into a private helper. Replace `readMiniFanCurveMode()` to use it.

Add this private method (after `readGpuOverclockMode()`):

```dart
/// Returns the hwmon directory path (e.g. `.../hwmon/hwmon0/`) or null.
Future<String?> _findFanHwmonDir() async {
  final hwmonDir = Directory(_fanHwmonBasePath);
  if (!await hwmonDir.exists()) {
    return null;
  }

  try {
    await for (final entity in hwmonDir.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = entity.path.split('/').last;
      if (name.startsWith('hwmon')) {
        return '${entity.path}/';
      }
    }
  } catch (_) {
    return null;
  }

  return null;
}
```

Replace `readMiniFanCurveMode()` body to use the helper:

```dart
Future<bool?> readMiniFanCurveMode() async {
  final hwmonPath = await _findFanHwmonDir();
  if (hwmonPath == null) {
    return null;
  }

  final value = await _readBoolFile('${hwmonPath}minifancurve');
  return value;
}
```

### Step 3: Add readFanCurve method

Add after `readMiniFanCurveMode()`:

```dart
Future<FanCurve?> readFanCurve() async {
  final hwmonPath = await _findFanHwmonDir();
  if (hwmonPath == null) {
    return null;
  }

  final fan1Max = await readIntFile('${hwmonPath}fan1_max');
  final fan2Max = await readIntFile('${hwmonPath}fan2_max');

  if (fan1Max == null || fan1Max == 0 || fan2Max == null || fan2Max == 0) {
    return null;
  }

  final points = <FanCurvePoint>[];
  for (var i = 1; i <= 10; i++) {
    final pwm1 =
        (await readIntFile('${hwmonPath}pwm1_auto_point${i}_pwm')) ?? 0;
    final pwm2 =
        (await readIntFile('${hwmonPath}pwm2_auto_point${i}_pwm')) ?? 0;
    final cpuLower =
        (await readIntFile('${hwmonPath}pwm1_auto_point${i}_temp_hyst')) ?? 0;
    final cpuUpper =
        (await readIntFile('${hwmonPath}pwm1_auto_point${i}_temp')) ?? 0;
    final gpuLower =
        (await readIntFile('${hwmonPath}pwm2_auto_point${i}_temp_hyst')) ?? 0;
    final gpuUpper =
        (await readIntFile('${hwmonPath}pwm2_auto_point${i}_temp')) ?? 0;
    final icLower =
        (await readIntFile('${hwmonPath}pwm3_auto_point${i}_temp_hyst')) ?? 0;
    final icUpper =
        (await readIntFile('${hwmonPath}pwm3_auto_point${i}_temp')) ?? 0;
    final accel =
        (await readIntFile('${hwmonPath}pwm1_auto_point${i}_accel')) ?? 0;
    final decel =
        (await readIntFile('${hwmonPath}pwm1_auto_point${i}_decel')) ?? 0;

    points.add(
      FanCurvePoint(
        fan1Rpm: _pwmToRpm(pwm1, fan1Max),
        fan2Rpm: _pwmToRpm(pwm2, fan2Max),
        cpuLowerTemp: cpuLower,
        cpuUpperTemp: cpuUpper,
        gpuLowerTemp: gpuLower,
        gpuUpperTemp: gpuUpper,
        icLowerTemp: icLower,
        icUpperTemp: icUpper,
        accel: accel,
        decel: decel,
      ),
    );
  }

  return FanCurve(name: 'custom', points: List.unmodifiable(points));
}

static int _pwmToRpm(int pwm, int maxRpm) {
  return (pwm / 255.0 * maxRpm).round();
}
```

### Step 4: Analyze

```bash
cd frontend/legion_frontend
flutter analyze lib/core/services/legion_sysfs_service.dart
```

Expected: no issues

### Step 5: Run all tests

```bash
cd frontend/legion_frontend
flutter test
```

Expected: all pass (existing tests should not break)

### Step 6: Commit

```bash
cd frontend/legion_frontend
git add lib/core/services/legion_sysfs_service.dart
git commit -m "feat(sysfs): add readFanCurve — reads 10-point fan curve from hwmon sysfs"
```

---

## Task 4: Add fan curve fields to snapshot, state, and event

**Files:**
- Modify: `lib/features/fans/models/fans_snapshot.dart`
- Modify: `lib/features/fans/bloc/fans_state.dart`
- Modify: `lib/features/fans/bloc/fans_event.dart`

### Step 1: Update FansSnapshot

Add import at top:
```dart
import 'fan_curve.dart';
```

Add to constructor, fields, and `props`:
```dart
// Constructor parameter (after maximumFanSpeedEnabled):
required this.fanCurve,

// Field declaration (after bool? maximumFanSpeedEnabled):
final FanCurve? fanCurve;

// props list (after maximumFanSpeedEnabled):
fanCurve,
```

### Step 2: Update FansState

Add import:
```dart
import '../models/fan_curve.dart';
```

**a) Constructor parameters** (after `required this.maximumFanSpeedEnabled,`):
```dart
required this.fanCurve,
required this.fanCurveDirty,
```

**b) Field declarations** (after `final bool? maximumFanSpeedEnabled;`):
```dart
final FanCurve? fanCurve;
final bool fanCurveDirty;
```

**c) `initial()` factory** (after `maximumFanSpeedEnabled: null,`):
```dart
fanCurve: null,
fanCurveDirty: false,
```

**d) `hasLoaded` getter** — add `|| fanCurve != null` to the OR chain.

**e) `copyWith` signature** (after `Object? maximumFanSpeedEnabled = _unset,`):
```dart
Object? fanCurve = _unset,
bool? fanCurveDirty,
```

**f) `copyWith` body** (after `maximumFanSpeedEnabled:` line):
```dart
fanCurve: fanCurve == _unset ? this.fanCurve : fanCurve as FanCurve?,
fanCurveDirty: fanCurveDirty ?? this.fanCurveDirty,
```

**g) `props` list** (after `maximumFanSpeedEnabled,`):
```dart
fanCurve,
fanCurveDirty,
```

### Step 3: Add events to fans_event.dart

Add import:
```dart
import '../models/fan_curve.dart';
```

Add at the end of the file:
```dart
final class FanCurvePointUpdated extends FansEvent {
  const FanCurvePointUpdated({required this.index, required this.point});

  final int index;
  final FanCurvePoint point;

  @override
  List<Object?> get props => [index, point];
}

final class FanCurveSaveRequested extends FansEvent {
  const FanCurveSaveRequested();
}
```

### Step 4: Analyze

```bash
cd frontend/legion_frontend
flutter analyze lib/features/fans/
```

Fix any compile errors (e.g. `FansSnapshot` constructor calls that now need `fanCurve:`). The only caller is `fans_repository.dart` — that will be fixed in Task 5.

### Step 5: Commit

```bash
cd frontend/legion_frontend
git add lib/features/fans/models/fans_snapshot.dart \
        lib/features/fans/bloc/fans_state.dart \
        lib/features/fans/bloc/fans_event.dart
git commit -m "feat(fans): add fanCurve fields to snapshot/state and fan curve events"
```

---

## Task 5: Add fan curve read/write to FansRepository

**Files:**
- Modify: `lib/features/fans/repository/fans_repository.dart`

### Step 1: Add import

```dart
import 'dart:io';
import '../models/fan_curve.dart';
```

### Step 2: Update loadSnapshot()

At the end of the reads inside `loadSnapshot()`, add:

```dart
final fanCurve = await _sysfsService.readFanCurve();
```

In the `FansSnapshot(...)` constructor call, add:
```dart
fanCurve: fanCurve,
```

### Step 3: Add writeFanCurveToHardware method

Add after `setMaximumFanSpeed()`:

```dart
static const _tempCurvePath = '/tmp/legion_frontend_custom_curve.yaml';

Future<void> writeFanCurveToHardware(FanCurve curve) async {
  // Write YAML to a temp file (unprivileged), then apply via pkexec.
  try {
    await File(_tempCurvePath).writeAsString(curve.toYaml());
  } catch (error) {
    throw FansRepositoryException(
      'Failed to write fan curve temp file: $error',
    );
  }

  await _runPrivilegedCommand(
    ['fancurve-write-file-to-hw', _tempCurvePath],
    method: 'fan_curve.write_to_hw',
    failurePrefix: 'Failed to write fan curve to hardware',
  );
}
```

### Step 4: Analyze

```bash
cd frontend/legion_frontend
flutter analyze lib/features/fans/repository/fans_repository.dart
```

Expected: no issues

### Step 5: Commit

```bash
cd frontend/legion_frontend
git add lib/features/fans/repository/fans_repository.dart
git commit -m "feat(fans): add fan curve read + writeFanCurveToHardware to FansRepository"
```

---

## Task 6: Wire fan curve in FansBloc

**Files:**
- Modify: `lib/features/fans/bloc/fans_bloc.dart`

### Step 1: Register handlers in constructor

After `on<MaximumFanSpeedSetRequested>(_onMaximumFanSpeedSetRequested);`, add:
```dart
on<FanCurvePointUpdated>(_onFanCurvePointUpdated);
on<FanCurveSaveRequested>(_onFanCurveSaveRequested);
```

### Step 2: Add handler methods

After `_onMaximumFanSpeedSetRequested(...)`, add:

```dart
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
```

### Step 3: Wire fanCurve in _reloadState

In the `state.copyWith(...)` call inside `_reloadState`, add after `maximumFanSpeedEnabled: snapshot.maximumFanSpeedEnabled,`:

```dart
// Only overwrite fanCurve from hardware if the user has no unsaved edits.
fanCurve: state.fanCurveDirty ? state.fanCurve : snapshot.fanCurve,
```

**Important:** because `fanCurve` in `copyWith` uses the `_unset` sentinel, you need to pass the value explicitly. Pass `state.fanCurve` when dirty (preserve edits) or `snapshot.fanCurve` when not dirty (overwrite from hardware).

### Step 4: Analyze

```bash
cd frontend/legion_frontend
flutter analyze lib/features/fans/bloc/fans_bloc.dart
```

Expected: no issues

### Step 5: Run all tests

```bash
cd frontend/legion_frontend
flutter test
```

Expected: all pass

### Step 6: Commit

```bash
cd frontend/legion_frontend
git add lib/features/fans/bloc/fans_bloc.dart
git commit -m "feat(fans): add FanCurvePointUpdated + FanCurveSaveRequested handlers in FansBloc"
```

---

## Task 7: Add Fan Curve editor section to FansPage

**Files:**
- Modify: `lib/features/fans/view/fans_page.dart`

### Step 1: Add imports

```dart
import '../bloc/fans_bloc.dart';
import '../models/fan_curve.dart';
```

(Check whether `fans_bloc.dart` is already imported — if so, skip that one.)

### Step 2: Add the Fan Curve section

Insert between the Fan Controls section and the `AppRefreshButton` (after the Fan Controls `const SizedBox(height: 16),`):

```dart
const SizedBox(height: 16),
AppSectionCard(
  title: 'Fan Curve',
  description:
      'Custom 10-point temperature/RPM curve. '
      'Lower temp = hysteresis threshold; Upper temp = trigger threshold.',
  children: [
    if (state.fanCurve == null)
      const ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text('Fan curve editor'),
        subtitle: Text('Unavailable — hwmon driver not detected.'),
      )
    else ...[
      const PrivilegedActionNotice(),
      const SizedBox(height: 8),
      _FanCurveTable(
        curve: state.fanCurve!,
        enabled: !state.isApplying,
        onPointChanged: (index, point) =>
            bloc.add(FanCurvePointUpdated(index: index, point: point)),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed:
            (state.fanCurveDirty && !state.isApplying)
            ? () async {
                final confirmed = await confirmPrivilegedAction(
                  context,
                  title: 'Apply fan curve',
                  message:
                      'Writing a custom fan curve requires privileged access and may prompt for authentication.',
                  confirmLabel: 'Apply',
                );
                if (!context.mounted || !confirmed) return;
                bloc.add(const FanCurveSaveRequested());
              }
            : null,
        icon: state.isApplying
            ? const SizedBox(
                width: 16,
                height: 16,
                child: YaruCircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.save),
        label: const Text('Apply to hardware'),
      ),
    ],
  ],
),
```

### Step 3: Add _FanCurveTable widget

Add this `StatefulWidget` at the bottom of the file (outside `FansPage`):

```dart
class _FanCurveTable extends StatefulWidget {
  const _FanCurveTable({
    required this.curve,
    required this.enabled,
    required this.onPointChanged,
  });

  final FanCurve curve;
  final bool enabled;
  final void Function(int index, FanCurvePoint point) onPointChanged;

  @override
  State<_FanCurveTable> createState() => _FanCurveTableState();
}

class _FanCurveTableState extends State<_FanCurveTable> {
  // 10 rows × 6 columns: cpuLo, cpuHi, gpuLo, gpuHi, fan1, fan2
  late final List<List<TextEditingController>> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      10,
      (i) {
        final p = widget.curve.points[i];
        return [
          TextEditingController(text: '${p.cpuLowerTemp}'),
          TextEditingController(text: '${p.cpuUpperTemp}'),
          TextEditingController(text: '${p.gpuLowerTemp}'),
          TextEditingController(text: '${p.gpuUpperTemp}'),
          TextEditingController(text: '${p.fan1Rpm}'),
          TextEditingController(text: '${p.fan2Rpm}'),
        ];
      },
    );
  }

  @override
  void didUpdateWidget(_FanCurveTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync controllers when curve is reset (e.g. after refresh), but only if
    // values changed externally (avoid clobbering ongoing user input).
    if (oldWidget.curve != widget.curve) {
      for (var i = 0; i < 10; i++) {
        final p = widget.curve.points[i];
        final vals = [
          '${p.cpuLowerTemp}',
          '${p.cpuUpperTemp}',
          '${p.gpuLowerTemp}',
          '${p.gpuUpperTemp}',
          '${p.fan1Rpm}',
          '${p.fan2Rpm}',
        ];
        for (var j = 0; j < 6; j++) {
          if (_controllers[i][j].text != vals[j]) {
            _controllers[i][j].text = vals[j];
          }
        }
      }
    }
  }

  @override
  void dispose() {
    for (final row in _controllers) {
      for (final c in row) {
        c.dispose();
      }
    }
    super.dispose();
  }

  void _commitRow(int index) {
    final row = _controllers[index];
    final cpuLo = int.tryParse(row[0].text) ?? widget.curve.points[index].cpuLowerTemp;
    final cpuHi = int.tryParse(row[1].text) ?? widget.curve.points[index].cpuUpperTemp;
    final gpuLo = int.tryParse(row[2].text) ?? widget.curve.points[index].gpuLowerTemp;
    final gpuHi = int.tryParse(row[3].text) ?? widget.curve.points[index].gpuUpperTemp;
    final fan1  = int.tryParse(row[4].text) ?? widget.curve.points[index].fan1Rpm;
    final fan2  = int.tryParse(row[5].text) ?? widget.curve.points[index].fan2Rpm;

    widget.onPointChanged(
      index,
      widget.curve.points[index].copyWith(
        cpuLowerTemp: cpuLo,
        cpuUpperTemp: cpuHi,
        gpuLowerTemp: gpuLo,
        gpuUpperTemp: gpuHi,
        fan1Rpm: fan1,
        fan2Rpm: fan2,
      ),
    );
  }

  Widget _cell(TextEditingController ctrl, int rowIndex) {
    return SizedBox(
      width: 64,
      child: TextFormField(
        controller: ctrl,
        enabled: widget.enabled,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        ),
        onEditingComplete: () => _commitRow(rowIndex),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 36,
        dataRowMinHeight: 40,
        dataRowMaxHeight: 52,
        columnSpacing: 8,
        columns: const [
          DataColumn(label: Text('#')),
          DataColumn(label: Text('CPU Lo (°C)')),
          DataColumn(label: Text('CPU Hi (°C)')),
          DataColumn(label: Text('GPU Lo (°C)')),
          DataColumn(label: Text('GPU Hi (°C)')),
          DataColumn(label: Text('Fan1 RPM')),
          DataColumn(label: Text('Fan2 RPM')),
        ],
        rows: List.generate(10, (i) {
          final row = _controllers[i];
          return DataRow(
            cells: [
              DataCell(Text('${i + 1}')),
              DataCell(_cell(row[0], i)),
              DataCell(_cell(row[1], i)),
              DataCell(_cell(row[2], i)),
              DataCell(_cell(row[3], i)),
              DataCell(_cell(row[4], i)),
              DataCell(_cell(row[5], i)),
            ],
          );
        }),
      ),
    );
  }
}
```

### Step 4: Run all tests

```bash
cd frontend/legion_frontend
flutter test
```

Expected: PASS — all tests including the 6 fan curve model tests.

### Step 5: Full analyze

```bash
cd frontend/legion_frontend
flutter analyze
```

Expected: no issues

### Step 6: Commit

```bash
cd frontend/legion_frontend
git add lib/features/fans/view/fans_page.dart
git commit -m "feat(fans): add 10-point fan curve table editor to Fans page

Closes LenovoLegionLinux-s21"
```

---

## Verification Checklist

Before declaring done:

- [ ] `flutter test` — all tests pass (≥6 new model tests in `test/features/fans/fan_curve_test.dart`)
- [ ] `flutter analyze` — zero issues
- [ ] `FanCurve.toYaml()` produces YAML with correct field names (`fan1_speed`, `cpu_lower_temp`, `enable_minifancurve`, etc.)
- [ ] `FanCurve.copyWithPoint(2, updated)` changes only point at index 2
- [ ] `FansState.initial().fanCurve` is `null`, `fanCurveDirty` is `false`
- [ ] When hwmon is unavailable, `readFanCurve()` returns null and UI shows an unavailability notice
- [ ] `FanCurvePointUpdated` sets `fanCurveDirty: true`
- [ ] `FanCurveSaveRequested` resets `fanCurveDirty: false` on success
- [ ] `_reloadState` preserves edited fan curve when `fanCurveDirty: true`
- [ ] `_FanCurveTable` syncs controllers on `didUpdateWidget` only when curve changes externally
- [ ] IC temps, accel, decel are preserved in the model and included in YAML but not shown in the table
- [ ] "Apply to hardware" button is disabled when not dirty or while applying
