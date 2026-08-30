import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/analytics/bloc/analytics_bloc.dart';
import 'package:legion_frontend/features/analytics/models/sensor_record.dart';
import 'package:legion_frontend/features/analytics/providers/analytics_provider.dart';
import 'package:legion_frontend/features/analytics/repository/analytics_repository.dart';
import 'package:legion_frontend/features/dgpu/bloc/dgpu_bloc.dart';
import 'package:legion_frontend/features/dgpu/bloc/dgpu_event.dart';
import 'package:legion_frontend/features/dgpu/models/dgpu_process.dart';
import 'package:legion_frontend/features/dgpu/models/dgpu_snapshot.dart';
import 'package:legion_frontend/features/dgpu/providers/dgpu_provider.dart';
import 'package:legion_frontend/features/dgpu/repository/dgpu_repository.dart';
import 'package:legion_frontend/features/dgpu/view/dgpu_page.dart';
import 'package:legion_frontend/features/power/bloc/power_bloc.dart';
import 'package:legion_frontend/features/power/bloc/power_event.dart';
import 'package:legion_frontend/features/power/models/power_mode.dart';
import 'package:legion_frontend/features/power/models/power_snapshot.dart';
import 'package:legion_frontend/features/power/providers/power_provider.dart';
import 'package:legion_frontend/features/power/repository/power_repository.dart';
import 'package:legion_frontend/features/sensors/bloc/live_sensor_bloc.dart';
import 'package:legion_frontend/features/sensors/bloc/live_sensor_event.dart';
import 'package:legion_frontend/features/sensors/models/live_sensor_snapshot.dart';
import 'package:legion_frontend/features/sensors/providers/live_sensor_provider.dart';
import 'package:legion_frontend/features/sensors/repository/live_sensor_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:yaru/yaru.dart';

class _MockDgpuRepository extends Mock implements DgpuRepository {}

class _MockLiveSensorRepository extends Mock implements LiveSensorRepository {}

class _MockPowerRepository extends Mock implements PowerRepository {}

class _MockAnalyticsRepository extends Mock implements AnalyticsRepository {}

void main() {
  testWidgets('dGPU handoff is responsive and shows live P-state', (
    tester,
  ) async {
    await _pumpPage(tester, width: 360, processes: const []);

    expect(find.text('NVIDIA GeForce RTX 4060'), findsOneWidget);
    expect(find.text('P2'), findsOneWidget);
    expect(find.text('Usage %'), findsOneWidget);
    expect(find.text('GPU working mode'), findsOneWidget);
    expect(find.text('Hybrid (iGPU + dGPU)'), findsOneWidget);
    expect(find.text('Processes on the dGPU'), findsOneWidget);
    expect(find.text('Discrete GPU'), findsNothing);
    expect(find.text('No process targets'), findsOneWidget);
    final killButton = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('No process targets'),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(killButton.onPressed, isNull);
    expect(
      find.byWidgetPredicate((widget) => widget is YaruPopupMenuButton),
      findsNWidgets(2),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('process confirmation names confirmed PIDs', (tester) async {
    await _pumpPage(
      tester,
      width: 900,
      processes: const [
        DgpuProcess(pid: 4242, name: 'blender', usedMemoryMib: 2048),
      ],
    );

    await tester.tap(find.text('Kill 1 processes'));
    await tester.pumpAndSettle();
    expect(find.text('Kill 1 GPU processes'), findsOneWidget);
    expect(find.textContaining('PIDs 4242'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    final restartButton = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('Restart PCI device'),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(restartButton.onPressed, isNull);
  });

  testWidgets('PCI restart confirmation names the discovered target', (
    tester,
  ) async {
    await _pumpPage(tester, width: 900, processes: const []);

    await tester.tap(find.text('Restart PCI device'));
    await tester.pumpAndSettle();
    expect(find.text('Restart GPU PCI device'), findsOneWidget);
    expect(
      find.text(
        'This removes 0000:01:00.0 from the PCI tree and rescans it. The GPU '
        'will briefly disappear. Close GPU applications first. Continue?',
      ),
      findsOneWidget,
    );
  });
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required double width,
  required List<DgpuProcess> processes,
}) async {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final dgpuRepository = _MockDgpuRepository();
  when(dgpuRepository.loadSnapshot).thenAnswer(
    (_) async => DgpuSnapshot(
      isActive: true,
      processes: processes,
      pciAddress: '0000:01:00.0',
      hybridModeEnabled: true,
      hybridModeSupported: true,
      name: 'NVIDIA Corporation AD107M',
    ),
  );
  final dgpuBloc = DgpuBloc(
    repository: dgpuRepository,
    pollInterval: const Duration(days: 1),
  );
  final dgpuLoaded = dgpuBloc.stream.firstWhere(
    (state) => !state.isLoading && state.isAvailable,
  );
  dgpuBloc.add(const DgpuStarted());
  await dgpuLoaded;

  final sensorRepository = _MockLiveSensorRepository();
  when(
    sensorRepository.loadSnapshot,
  ).thenAnswer((_) async => _liveSensorSnapshot);
  final sensorBloc = LiveSensorBloc(
    repository: sensorRepository,
    pollInterval: const Duration(days: 1),
  );
  final sensorsLoaded = sensorBloc.stream.firstWhere(
    (state) => !state.isLoading,
  );
  sensorBloc.add(const LiveSensorStarted());
  await sensorsLoaded;

  final powerRepository = _MockPowerRepository();
  when(powerRepository.loadSnapshot).thenAnswer((_) async => _powerSnapshot);
  final powerBloc = PowerBloc(
    repository: powerRepository,
    pollInterval: const Duration(days: 1),
  );
  final powerLoaded = powerBloc.stream.firstWhere((state) => !state.isLoading);
  powerBloc.add(const PowerStarted());
  await powerLoaded;

  final history = [
    SensorRecord(
      timestamp: DateTime.now().subtract(const Duration(minutes: 1)),
      gpuUtilPercent: 32,
      gpuPowerDrawW: 28,
      gpuTempC: 61,
    ),
    SensorRecord(
      timestamp: DateTime.now(),
      gpuUtilPercent: 42,
      gpuPowerDrawW: 38,
      gpuTempC: 64,
    ),
  ];
  final analyticsRepository = _MockAnalyticsRepository();
  when(analyticsRepository.pruneOldRecords).thenAnswer((_) async {});
  when(analyticsRepository.recordReading).thenAnswer((_) async => history.last);
  when(
    () => analyticsRepository.readHistory(since: any(named: 'since')),
  ).thenReturn(history);
  final analyticsBloc = AnalyticsBloc(
    repository: analyticsRepository,
    pollInterval: const Duration(days: 1),
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dgpuBlocProvider.overrideWith((ref) => dgpuBloc),
        liveSensorBlocProvider.overrideWith((ref) => sensorBloc),
        powerBlocProvider.overrideWith((ref) => powerBloc),
        analyticsBlocProvider.overrideWith((ref) => analyticsBloc),
      ],
      child: YaruTheme(
        data: const YaruThemeData(),
        builder: (context, yaru, child) => MaterialApp(
          theme: yaru.theme,
          darkTheme: yaru.darkTheme,
          themeMode: ThemeMode.dark,
          home: const Scaffold(body: DgpuPage()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _liveSensorSnapshot = LiveSensorSnapshot(
  cpuName: 'Test CPU',
  cpuTempC: 62,
  cpuUtilPercent: 18,
  cpuClockGhz: 3.1,
  cpuPackagePowerW: 24,
  fan1Rpm: null,
  fan2Rpm: null,
  gpuName: 'NVIDIA GeForce RTX 4060',
  gpuTempC: 64,
  gpuUtilPercent: 42,
  gpuClockGhz: 1.8,
  gpuVramUsedGb: 2.1,
  gpuVramTotalGb: 8,
  gpuFanPercent: 35,
  gpuPowerDrawW: 38,
  gpuIsDiscrete: true,
  gpuPerformanceState: 'P2',
  motherboardTempC: null,
  batteryPercent: 94,
  batteryCharging: false,
  batteryPowerDrawW: 0,
  diskTempC: null,
);

const _powerSnapshot = PowerSnapshot(
  currentMode: PowerMode('balanced'),
  availableModes: [PowerMode('balanced')],
  powerLimits: [],
  cpuOverclockEnabled: null,
  gpuOverclockEnabled: false,
);
