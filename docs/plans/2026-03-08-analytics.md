# System Analytics Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Surface live CPU/GPU temperature, fan RPM readings in the UI and persist long-term history to disk using Hive CE, so graphs survive restarts and can show days/weeks of data.

**Architecture:**
- New `analytics` feature: `bloc/event/state` + `repository` + `view`, same as all other features.
- `LegionSysfsService` gets new unprivileged sysfs methods: `readFan1Rpm`, `readFan2Rpm`, `readCpuTempC`, `readGpuTempC`.
- A `SensorRecord` Hive model (with auto-generated `TypeAdapter`) stores each reading timestamped to disk.
- `AnalyticsRepository` wraps the Hive box: reads history within a time window, appends new readings, prunes old data.
- `AnalyticsBloc` polls every 3 seconds, persists each reading, and emits updated state.
- `AppSection.analytics` nav entry + `AnalyticsPage` with live readings and `fl_chart` line charts.
- **Data retention:** keep readings from the last **30 days**; prune on write.

**Tech Stack:** Dart/Flutter, `riverbloc`, `hive_ce: ^2.19.3`, `hive_ce_flutter`, `fl_chart`, `yaru`

---

## Task 1: Add dependencies

**Files:**
- Modify: `pubspec.yaml`

**Step 1: Add packages**

```bash
flutter pub add hive_ce:'^2.19.3' hive_ce_flutter fl_chart
flutter pub add dev:hive_ce_generator build_runner
```

**Step 2: Verify**

```bash
flutter pub get
```
Expected: resolves with no errors.

**Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: add hive_ce, fl_chart dependencies for analytics"
```

---

## Task 2: Add live sensor reads to LegionSysfsService

**Files:**
- Modify: `lib/core/services/legion_sysfs_service.dart`
- Test: `test/core/services/legion_sysfs_service_analytics_test.dart`

### Step 1: Write the failing tests

```dart
// test/core/services/legion_sysfs_service_analytics_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/services/legion_sysfs_service.dart';

void main() {
  late Directory tmpDir;
  late LegionSysfsService service;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('sysfs_test_');
    service = LegionSysfsService();
  });

  tearDown(() async => tmpDir.delete(recursive: true));

  group('parseFanRpm', () {
    test('returns RPM when file contains valid integer', () async {
      await File('${tmpDir.path}/fan1_input').writeAsString('3200\n');
      expect(await service.readIntFile('${tmpDir.path}/fan1_input'), 3200);
    });

    test('returns null when file does not exist', () async {
      expect(await service.readIntFile('${tmpDir.path}/nonexistent'), isNull);
    });
  });

  group('milliDegreesToC', () {
    test('converts millidegrees to degrees', () {
      expect(LegionSysfsService.milliDegreesToC(45000), 45.0);
      expect(LegionSysfsService.milliDegreesToC(72500), 72.5);
    });
  });
}
```

**Step 2: Run to verify it fails**

```bash
flutter test test/core/services/legion_sysfs_service_analytics_test.dart
```
Expected: FAIL — `milliDegreesToC` does not exist.

**Step 3: Implement in `legion_sysfs_service.dart`**

Add near the top of the class body, alongside the existing path constants:

```dart
static const String _hwmonBasePath = '/sys/class/hwmon';

/// Convert hwmon millidegrees Celsius to degrees Celsius.
static double milliDegreesToC(int milliDegrees) => milliDegrees / 1000.0;
```

Add after `readGpuOverclockMode()`:

```dart
/// Current CPU fan speed in RPM. Returns null if unavailable.
Future<int?> readFan1Rpm() async {
  final p = await _findFanHwmonDir();
  return p == null ? null : readIntFile('${p}fan1_input');
}

/// Current GPU fan speed in RPM. Returns null if unavailable.
Future<int?> readFan2Rpm() async {
  final p = await _findFanHwmonDir();
  return p == null ? null : readIntFile('${p}fan2_input');
}

/// CPU package temperature in °C. Returns null if unavailable.
Future<double?> readCpuTempC() async {
  final path = await _findHwmonTempInput(
    driverNames: {'coretemp', 'k10temp'}, label: 'Package id 0', fallbackIndex: 1,
  );
  final raw = path == null ? null : await readIntFile(path);
  return raw == null ? null : milliDegreesToC(raw);
}

/// GPU temperature in °C. Returns null if unavailable.
Future<double?> readGpuTempC() async {
  final path = await _findHwmonTempInput(
    driverNames: {'nouveau', 'amdgpu', 'nvidia', 'radeon'}, fallbackIndex: 1,
  );
  final raw = path == null ? null : await readIntFile(path);
  return raw == null ? null : milliDegreesToC(raw);
}

Future<String?> _findHwmonTempInput({
  required Set<String> driverNames,
  String? label,
  int fallbackIndex = 1,
}) async {
  final dir = Directory(_hwmonBasePath);
  if (!await dir.exists()) return null;
  try {
    await for (final entity in dir.list(followLinks: true)) {
      if (entity is! Directory) continue;
      final nameFile = File('${entity.path}/name');
      if (!await nameFile.exists()) continue;
      final name = (await nameFile.readAsString()).trim().toLowerCase();
      if (!driverNames.contains(name)) continue;
      if (label != null) {
        for (var i = 1; i <= 32; i++) {
          final lf = File('${entity.path}/temp${i}_label');
          if (!await lf.exists()) continue;
          if ((await lf.readAsString()).trim() == label) {
            return '${entity.path}/temp${i}_input';
          }
        }
      }
      final fb = '${entity.path}/temp${fallbackIndex}_input';
      if (await File(fb).exists()) return fb;
    }
  } catch (_) {}
  return null;
}
```

**Step 4: Run test to verify it passes**

```bash
flutter test test/core/services/legion_sysfs_service_analytics_test.dart
```

**Step 5: Commit**

```bash
git add lib/core/services/legion_sysfs_service.dart test/core/services/legion_sysfs_service_analytics_test.dart
git commit -m "feat(analytics): add live fan RPM and temperature reads to LegionSysfsService"
```

---

## Task 3: SensorRecord Hive model (with TypeAdapter)

**Files:**
- Create: `lib/features/analytics/models/sensor_record.dart`
- Create: `lib/features/analytics/models/sensor_record.g.dart` ← generated

**Step 1: Write the model**

Hive CE supports code generation. Annotate the model:

```dart
// lib/features/analytics/models/sensor_record.dart
import 'package:hive_ce/hive.dart';

part 'sensor_record.g.dart';

@HiveType(typeId: 1)
class SensorRecord extends HiveObject {
  SensorRecord({
    required this.timestamp,
    this.fan1Rpm,
    this.fan2Rpm,
    this.cpuTempC,
    this.gpuTempC,
  });

  @HiveField(0)
  DateTime timestamp;

  @HiveField(1)
  int? fan1Rpm;

  @HiveField(2)
  int? fan2Rpm;

  @HiveField(3)
  double? cpuTempC;

  @HiveField(4)
  double? gpuTempC;
}
```

> **Note:** `typeId: 1` — reserve `0` for future use by other features. If another Hive model already uses `1`, pick the next free integer.

**Step 2: Generate the TypeAdapter**

```bash
dart run build_runner build --delete-conflicting-outputs
```
Expected: `sensor_record.g.dart` created in the same directory.

**Step 3: No unit test needed** — the generated adapter is tested by the repository integration test in Task 4.

**Step 4: Commit**

```bash
git add lib/features/analytics/models/
git commit -m "feat(analytics): add SensorRecord Hive model and generated TypeAdapter"
```

---

## Task 4: AnalyticsRepository (Hive persistence)

**Files:**
- Create: `lib/features/analytics/repository/analytics_repository.dart`
- Test: `test/features/analytics/analytics_repository_test.dart`

### Step 1: Write failing tests

```dart
// test/features/analytics/analytics_repository_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:legion_frontend/core/services/legion_sysfs_service.dart';
import 'package:legion_frontend/features/analytics/models/sensor_record.dart';
import 'package:legion_frontend/features/analytics/repository/analytics_repository.dart';
import 'package:mocktail/mocktail.dart';

class MockSysfsService extends Mock implements LegionSysfsService {}

void main() {
  late Directory tmpDir;
  late MockSysfsService sysfs;
  late AnalyticsRepository repo;
  late Box<SensorRecord> box;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('hive_test_');
    Hive.init(tmpDir.path);
    Hive.registerAdapter(SensorRecordAdapter());
    box = await Hive.openBox<SensorRecord>('sensor_records_test');

    sysfs = MockSysfsService();
    when(() => sysfs.readFan1Rpm()).thenAnswer((_) async => 2500);
    when(() => sysfs.readFan2Rpm()).thenAnswer((_) async => 2200);
    when(() => sysfs.readCpuTempC()).thenAnswer((_) async => 55.0);
    when(() => sysfs.readGpuTempC()).thenAnswer((_) async => 48.0);

    repo = AnalyticsRepository(sysfsService: sysfs, box: box);
  });

  tearDown(() async {
    await Hive.close();
    await tmpDir.delete(recursive: true);
  });

  test('recordReading persists a SensorRecord to Hive', () async {
    await repo.recordReading();
    expect(box.length, 1);
    expect(box.values.first.fan1Rpm, 2500);
  });

  test('readHistory returns all records within the window', () async {
    await repo.recordReading();
    final history = repo.readHistory(since: DateTime.now().subtract(const Duration(hours: 1)));
    expect(history.length, 1);
  });

  test('prune removes records older than retention', () async {
    // Insert an old record manually
    await box.add(SensorRecord(
      timestamp: DateTime.now().subtract(const Duration(days: 31)),
      fan1Rpm: 999,
    ));
    await repo.pruneOldRecords();
    expect(box.length, 0);
  });
}
```

**Step 2: Run to verify it fails**

```bash
flutter test test/features/analytics/analytics_repository_test.dart
```
Expected: FAIL — `AnalyticsRepository` not found.

**Step 3: Implement repository**

```dart
// lib/features/analytics/repository/analytics_repository.dart
import 'package:hive_ce/hive.dart';
import '../../../core/services/legion_sysfs_service.dart';
import '../models/sensor_record.dart';

class AnalyticsRepository {
  const AnalyticsRepository({
    required LegionSysfsService sysfsService,
    required Box<SensorRecord> box,
    Duration retention = const Duration(days: 30),
  }) : _sysfsService = sysfsService,
       _box = box,
       _retention = retention;

  final LegionSysfsService _sysfsService;
  final Box<SensorRecord> _box;
  final Duration _retention;

  /// Read all four sensors in parallel and persist the result.
  Future<SensorRecord> recordReading() async {
    final results = await Future.wait([
      _sysfsService.readFan1Rpm(),
      _sysfsService.readFan2Rpm(),
      _sysfsService.readCpuTempC(),
      _sysfsService.readGpuTempC(),
    ]);
    final record = SensorRecord(
      timestamp: DateTime.now(),
      fan1Rpm: results[0] as int?,
      fan2Rpm: results[1] as int?,
      cpuTempC: results[2] as double?,
      gpuTempC: results[3] as double?,
    );
    await _box.add(record);
    return record;
  }

  /// Return all records with timestamp >= [since], sorted oldest-first.
  List<SensorRecord> readHistory({required DateTime since}) {
    return _box.values
        .where((r) => r.timestamp.isAfter(since))
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  /// Delete records older than [_retention]. Call periodically (e.g. on startup).
  Future<void> pruneOldRecords() async {
    final cutoff = DateTime.now().subtract(_retention);
    final stale = _box.values.where((r) => r.timestamp.isBefore(cutoff)).toList();
    for (final record in stale) {
      await record.delete();
    }
  }
}
```

**Step 4: Run test to verify it passes**

```bash
flutter test test/features/analytics/analytics_repository_test.dart
```

**Step 5: Commit**

```bash
git add lib/features/analytics/repository/ test/features/analytics/analytics_repository_test.dart
git commit -m "feat(analytics): add AnalyticsRepository with Hive CE persistence and 30-day retention"
```

---

## Task 5: AnalyticsBloc

**Files:**
- Create: `lib/features/analytics/bloc/analytics_event.dart`
- Create: `lib/features/analytics/bloc/analytics_state.dart`
- Create: `lib/features/analytics/bloc/analytics_bloc.dart`
- Test: `test/features/analytics/analytics_bloc_test.dart`

### Step 1: Write failing tests

```dart
// test/features/analytics/analytics_bloc_test.dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/analytics/bloc/analytics_bloc.dart';
import 'package:legion_frontend/features/analytics/bloc/analytics_event.dart';
import 'package:legion_frontend/features/analytics/bloc/analytics_state.dart';
import 'package:legion_frontend/features/analytics/models/sensor_record.dart';
import 'package:legion_frontend/features/analytics/repository/analytics_repository.dart';
import 'package:mocktail/mocktail.dart';

class MockAnalyticsRepository extends Mock implements AnalyticsRepository {}

void main() {
  late MockAnalyticsRepository repo;

  setUp(() {
    repo = MockAnalyticsRepository();
    when(() => repo.recordReading()).thenAnswer((_) async =>
        SensorRecord(timestamp: DateTime(2024), fan1Rpm: 3000, cpuTempC: 60.0));
    when(() => repo.readHistory(since: any(named: 'since'))).thenReturn([
      SensorRecord(timestamp: DateTime(2024), fan1Rpm: 3000, cpuTempC: 60.0),
    ]);
    when(() => repo.pruneOldRecords()).thenAnswer((_) async {});
  });

  group('AnalyticsTicked', () {
    blocTest<AnalyticsBloc, AnalyticsState>(
      'records a reading and updates history',
      build: () => AnalyticsBloc(repository: repo),
      seed: () => AnalyticsState.initial(),
      act: (bloc) => bloc.add(const AnalyticsTicked()),
      expect: () => [
        isA<AnalyticsState>().having((s) => s.history.length, 'history length', greaterThan(0)),
      ],
    );
  });
}
```

**Step 2: Run to verify it fails**

```bash
flutter test test/features/analytics/analytics_bloc_test.dart
```

**Step 3: Implement events**

```dart
// lib/features/analytics/bloc/analytics_event.dart
import 'package:equatable/equatable.dart';

sealed class AnalyticsEvent extends Equatable {
  const AnalyticsEvent();
  @override List<Object?> get props => const [];
}

final class AnalyticsStarted extends AnalyticsEvent { const AnalyticsStarted(); }
final class AnalyticsTicked extends AnalyticsEvent { const AnalyticsTicked(); }

/// Change the displayed time window on the graph.
final class AnalyticsWindowChanged extends AnalyticsEvent {
  const AnalyticsWindowChanged(this.window);
  final AnalyticsTimeWindow window;
  @override List<Object?> get props => [window];
}
```

**Step 4: Implement state**

```dart
// lib/features/analytics/bloc/analytics_state.dart
import 'package:equatable/equatable.dart';
import '../models/sensor_record.dart';

enum AnalyticsTimeWindow { lastHour, last6h, last24h, last7d, last30d }

extension AnalyticsTimeWindowDuration on AnalyticsTimeWindow {
  Duration get duration => switch (this) {
    AnalyticsTimeWindow.lastHour => const Duration(hours: 1),
    AnalyticsTimeWindow.last6h   => const Duration(hours: 6),
    AnalyticsTimeWindow.last24h  => const Duration(hours: 24),
    AnalyticsTimeWindow.last7d   => const Duration(days: 7),
    AnalyticsTimeWindow.last30d  => const Duration(days: 30),
  };

  String get label => switch (this) {
    AnalyticsTimeWindow.lastHour => '1h',
    AnalyticsTimeWindow.last6h   => '6h',
    AnalyticsTimeWindow.last24h  => '24h',
    AnalyticsTimeWindow.last7d   => '7d',
    AnalyticsTimeWindow.last30d  => '30d',
  };
}

class AnalyticsState extends Equatable {
  const AnalyticsState({
    required this.history,
    required this.window,
    required this.errorMessage,
  });

  factory AnalyticsState.initial() => const AnalyticsState(
    history: [],
    window: AnalyticsTimeWindow.lastHour,
    errorMessage: null,
  );

  final List<SensorRecord> history;
  final AnalyticsTimeWindow window;
  final String? errorMessage;

  SensorRecord? get latest => history.isEmpty ? null : history.last;

  AnalyticsState copyWith({
    List<SensorRecord>? history,
    AnalyticsTimeWindow? window,
    Object? errorMessage = _unset,
  }) => AnalyticsState(
    history: history ?? this.history,
    window: window ?? this.window,
    errorMessage: errorMessage == _unset ? this.errorMessage : errorMessage as String?,
  );

  static const _unset = Object();

  @override
  List<Object?> get props => [history, window, errorMessage];
}
```

**Step 5: Implement AnalyticsBloc**

```dart
// lib/features/analytics/bloc/analytics_bloc.dart
import 'dart:async';
import 'package:riverbloc/riverbloc.dart';
import '../repository/analytics_repository.dart';
import 'analytics_event.dart';
import 'analytics_state.dart';

class AnalyticsBloc extends Bloc<AnalyticsEvent, AnalyticsState> {
  AnalyticsBloc({
    required AnalyticsRepository repository,
    Duration pollInterval = const Duration(seconds: 3),
  }) : _repository = repository,
       _pollInterval = pollInterval,
       super(AnalyticsState.initial()) {
    on<AnalyticsStarted>(_onStarted);
    on<AnalyticsTicked>(_onTicked);
    on<AnalyticsWindowChanged>(_onWindowChanged);
  }

  final AnalyticsRepository _repository;
  final Duration _pollInterval;
  Timer? _pollTimer;
  bool _started = false;

  Future<void> _onStarted(AnalyticsStarted _, Emitter<AnalyticsState> emit) async {
    if (_started) return;
    _started = true;
    await _repository.pruneOldRecords();
    await _tick(emit);
    _pollTimer = Timer.periodic(_pollInterval, (_) => add(const AnalyticsTicked()));
  }

  Future<void> _onTicked(AnalyticsTicked _, Emitter<AnalyticsState> emit) async {
    await _tick(emit);
  }

  Future<void> _onWindowChanged(AnalyticsWindowChanged event, Emitter<AnalyticsState> emit) async {
    final since = DateTime.now().subtract(event.window.duration);
    emit(state.copyWith(
      window: event.window,
      history: _repository.readHistory(since: since),
    ));
  }

  Future<void> _tick(Emitter<AnalyticsState> emit) async {
    try {
      await _repository.recordReading();
      final since = DateTime.now().subtract(state.window.duration);
      emit(state.copyWith(
        history: _repository.readHistory(since: since),
        errorMessage: null,
      ));
    } catch (error) {
      emit(state.copyWith(errorMessage: 'Sensor read failed: $error'));
    }
  }

  @override
  Future<void> close() {
    _pollTimer?.cancel();
    return super.close();
  }
}
```

**Step 6: Run test to verify it passes**

```bash
flutter test test/features/analytics/analytics_bloc_test.dart
```

**Step 7: Commit**

```bash
git add lib/features/analytics/bloc/ test/features/analytics/analytics_bloc_test.dart
git commit -m "feat(analytics): add AnalyticsBloc with polling, time window selection, and Hive persistence"
```

---

## Task 6: Hive initialisation and Riverpod providers

**Files:**
- Modify: `lib/main.dart` — init Hive, register adapter, open box before `runApp`
- Create: `lib/features/analytics/providers/analytics_provider.dart`
- Modify: `lib/core/providers/system_services_provider.dart` — expose the Hive box

### Step 1: Initialise Hive in main.dart

In `main()`, before `runApp(...)`:

```dart
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'features/analytics/models/sensor_record.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  Hive.registerAdapter(SensorRecordAdapter());
  await Hive.openBox<SensorRecord>('sensor_records');
  runApp(const ProviderScope(child: LegionFrontendApp()));
}
```

### Step 2: Expose the box via a provider

Add to `lib/core/providers/system_services_provider.dart`:

```dart
import 'package:hive_ce/hive.dart';
import '../../features/analytics/models/sensor_record.dart';

final sensorRecordBoxProvider = Provider<Box<SensorRecord>>(
  (ref) => Hive.box<SensorRecord>('sensor_records'),
);
```

### Step 3: Create analytics providers

```dart
// lib/features/analytics/providers/analytics_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverbloc/riverbloc.dart';
import '../../../core/providers/system_services_provider.dart';
import '../bloc/analytics_bloc.dart';
import '../bloc/analytics_state.dart';
import '../repository/analytics_repository.dart';

final analyticsRepositoryProvider = Provider<AnalyticsRepository>((ref) {
  return AnalyticsRepository(
    sysfsService: ref.watch(legionSysfsServiceProvider),
    box: ref.watch(sensorRecordBoxProvider),
  );
});

final analyticsBlocProvider = BlocProvider<AnalyticsBloc, AnalyticsState>((ref) {
  return AnalyticsBloc(repository: ref.watch(analyticsRepositoryProvider));
});
```

**Step 4: Commit**

```bash
git add lib/main.dart lib/core/providers/system_services_provider.dart lib/features/analytics/providers/analytics_provider.dart
git commit -m "feat(analytics): init Hive in main, wire Riverpod providers"
```

---

## Task 7: Navigation section and AnalyticsPage UI

**Files:**
- Modify: `lib/features/navigation/models/app_section.dart`
- Modify: `lib/features/navigation/view/navigation_shell.dart`
- Create: `lib/features/analytics/view/analytics_page.dart`

### Step 1: Add AppSection.analytics

In `app_section.dart`, add `analytics` after `dgpu`:

```dart
enum AppSection {
  dashboard, power, fans, battery, displayLighting, bootLogo, dgpu,
  analytics, // ← NEW
  automation, settings, about,
}
```

Add to all three extension switch blocks:
```dart
case AppSection.analytics:
  return 'Analytics';               // label
case AppSection.analytics:
  return Icons.show_chart_outlined; // icon
case AppSection.analytics:
  return YaruIcons.chart_line;      // yaruIcon
```

### Step 2: Wire in NavigationShell

```dart
import '../../analytics/view/analytics_page.dart';
// in _buildPage:
case AppSection.analytics: return const AnalyticsPage();
```

### Step 3: Implement AnalyticsPage

The page:
- Dispatches `AnalyticsStarted` on `initState`
- Shows a live readings row (fan1, fan2, CPU °C, GPU °C) from `state.latest`
- Shows a `SegmentedButton` to pick the time window (1h / 6h / 24h / 7d / 30d)
- Shows two `LineChart` (fl_chart) panels: one for temperatures, one for fan speeds

```dart
// lib/features/analytics/view/analytics_page.dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../bloc/analytics_event.dart';
import '../bloc/analytics_state.dart';
import '../models/sensor_record.dart';
import '../providers/analytics_provider.dart';

class AnalyticsPage extends ConsumerStatefulWidget {
  const AnalyticsPage({super.key});

  @override
  ConsumerState<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends ConsumerState<AnalyticsPage> {
  @override
  void initState() {
    super.initState();
    ref.read(analyticsBlocProvider.bloc).add(const AnalyticsStarted());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(analyticsBlocProvider);
    final latest = state.latest;
    final history = state.history;
    final bloc = ref.read(analyticsBlocProvider.bloc);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (state.errorMessage != null)
            Text(state.errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error)),

          // Live reading tiles
          _ReadingRow('CPU Fan', latest?.fan1Rpm != null ? '${latest!.fan1Rpm} RPM' : '—'),
          _ReadingRow('GPU Fan', latest?.fan2Rpm != null ? '${latest!.fan2Rpm} RPM' : '—'),
          _ReadingRow('CPU Temp', latest?.cpuTempC != null ? '${latest!.cpuTempC!.toStringAsFixed(1)} °C' : '—'),
          _ReadingRow('GPU Temp', latest?.gpuTempC != null ? '${latest!.gpuTempC!.toStringAsFixed(1)} °C' : '—'),

          const SizedBox(height: 16),

          // Time window picker
          SegmentedButton<AnalyticsTimeWindow>(
            segments: AnalyticsTimeWindow.values.map((w) =>
                ButtonSegment(value: w, label: Text(w.label))).toList(),
            selected: {state.window},
            onSelectionChanged: (sel) =>
                bloc.add(AnalyticsWindowChanged(sel.first)),
          ),

          const SizedBox(height: 24),

          if (history.length > 1) ...[
            Text('Temperature (°C)', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SizedBox(height: 140, child: _TemperatureChart(history: history)),
            const SizedBox(height: 20),
            Text('Fan Speed (RPM)', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SizedBox(height: 140, child: _FanSpeedChart(history: history)),
          ] else
            const Center(child: Text('Collecting data…')),
        ],
      ),
    );
  }
}

class _ReadingRow extends StatelessWidget {
  const _ReadingRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [Text(label), Text(value, style: const TextStyle(fontWeight: FontWeight.bold))],
    ),
  );
}

class _TemperatureChart extends StatelessWidget {
  const _TemperatureChart({required this.history});
  final List<SensorRecord> history;

  @override
  Widget build(BuildContext context) {
    spots(double? Function(SensorRecord) pick) => history
        .asMap()
        .entries
        .where((e) => pick(e.value) != null)
        .map((e) => FlSpot(e.key.toDouble(), pick(e.value)!))
        .toList();

    return LineChart(LineChartData(
      lineBarsData: [
        LineChartBarData(spots: spots((r) => r.cpuTempC), isCurved: true, color: Colors.orange, dotData: const FlDotData(show: false)),
        LineChartBarData(spots: spots((r) => r.gpuTempC), isCurved: true, color: Colors.blue, dotData: const FlDotData(show: false)),
      ],
      titlesData: const FlTitlesData(show: false),
      borderData: FlBorderData(show: false),
      gridData: const FlGridData(show: false),
    ));
  }
}

class _FanSpeedChart extends StatelessWidget {
  const _FanSpeedChart({required this.history});
  final List<SensorRecord> history;

  @override
  Widget build(BuildContext context) {
    spots(int? Function(SensorRecord) pick) => history
        .asMap()
        .entries
        .where((e) => pick(e.value) != null)
        .map((e) => FlSpot(e.key.toDouble(), pick(e.value)!.toDouble()))
        .toList();

    return LineChart(LineChartData(
      lineBarsData: [
        LineChartBarData(spots: spots((r) => r.fan1Rpm), isCurved: true, color: Colors.green, dotData: const FlDotData(show: false)),
        LineChartBarData(spots: spots((r) => r.fan2Rpm), isCurved: true, color: Colors.purple, dotData: const FlDotData(show: false)),
      ],
      titlesData: const FlTitlesData(show: false),
      borderData: FlBorderData(show: false),
      gridData: const FlGridData(show: false),
    ));
  }
}
```

**Step 4: Commit**

```bash
git add lib/features/analytics/view/ lib/features/navigation/models/app_section.dart lib/features/navigation/view/navigation_shell.dart
git commit -m "feat(analytics): add Analytics nav section and page with fl_chart time-series graphs"
```

---

## Task 8: Final verification

**Step 1: Full test suite**

```bash
flutter test --reporter=expanded
```
Expected: all tests pass.

**Step 2: Static analysis**

```bash
flutter analyze
```
Expected: no issues.

**Step 3: Smoke test**

```bash
flutter run -d linux
```
Navigate to **Analytics**. Confirm:
- Live readings update every 3 seconds
- Graphs appear after a few seconds of data
- Time window picker switches between 1h / 6h / 24h / 7d / 30d correctly
- Data survives restarting the app

**Step 4: Close bd issue**

```bash
cd /home/prnice/Projects/personal/LenovoLegionLinux && bd close okf.21
```
