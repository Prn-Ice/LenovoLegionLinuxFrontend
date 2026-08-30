import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/analytics/bloc/analytics_bloc.dart';
import 'package:legion_frontend/features/analytics/models/sensor_record.dart';
import 'package:legion_frontend/features/analytics/providers/analytics_provider.dart';
import 'package:legion_frontend/features/analytics/repository/analytics_repository.dart';
import 'package:legion_frontend/features/analytics/view/widgets/telemetry_history_card.dart';
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
    expect(find.text('Graphics mode'), findsOneWidget);
    expect(find.text('Hybrid'), findsOneWidget);
    expect(find.text('Configured: Hybrid'), findsOneWidget);
    expect(find.text('Integrated only'), findsOneWidget);
    expect(find.text('Discrete only'), findsOneWidget);
    expect(find.text('GPU performance'), findsOneWidget);
    expect(find.text('Processes on the dGPU'), findsOneWidget);
    expect(find.text('Discrete GPU'), findsNothing);
    expect(find.byKey(const ValueKey('gpu-vendor-nvidia')), findsOneWidget);
    expect(
      tester
          .widget<TelemetryHistoryCard>(find.byType(TelemetryHistoryCard))
          .accentColor,
      const Color(0xFF3A9D4F),
    );
    expect(find.byType(YaruSwitch), findsOneWidget);
    for (final toggle in tester.widgetList<YaruSwitch>(
      find.byType(YaruSwitch),
    )) {
      expect(toggle.selectedColor, const Color(0xFF3A9D4F));
    }
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

  testWidgets('graphics modes expose only the supported backend choices', (
    tester,
  ) async {
    final dgpuRepository = await _pumpPage(
      tester,
      width: 900,
      processes: const [],
    );

    final hybrid = find.byKey(const ValueKey('graphics-mode-hybrid'));
    await tester.ensureVisible(hybrid);
    await tester.tap(hybrid);
    await tester.pumpAndSettle();
    expect(find.text('Configure Hybrid'), findsNothing);
    verifyNever(() => dgpuRepository.setHybridMode(any()));

    final integrated = find.byKey(
      const ValueKey('graphics-mode-integratedOnly'),
    );
    await tester.ensureVisible(integrated);
    final integratedControl = tester.widget<YaruRadio>(
      find.byKey(const ValueKey('graphics-mode-integratedOnly-control')),
    );
    expect(integratedControl.onChanged, isNull);
    await tester.tap(integrated, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Configure Integrated only'), findsNothing);
    verifyNever(() => dgpuRepository.setHybridMode(any()));

    final discrete = find.byKey(const ValueKey('graphics-mode-discreteOnly'));
    await tester.ensureVisible(discrete);
    await tester.tap(discrete);
    await tester.pumpAndSettle();
    expect(find.text('Configure Discrete only'), findsOneWidget);
    expect(find.textContaining('A reboot is required'), findsOneWidget);
    await tester.tap(find.text('Configure mode'));
    await tester.pumpAndSettle();
    verify(() => dgpuRepository.setHybridMode(false)).called(1);
    expect(find.textContaining('Graphics mode configured'), findsNothing);
  });

  testWidgets('GPU identity uses the reported vendor mark', (tester) async {
    for (final vendor in const {
      'AMD Radeon RX 7600S': 'amd',
      'Intel Arc A770M': 'intel',
    }.entries) {
      await _pumpPage(
        tester,
        width: 360,
        processes: const [],
        gpuName: vendor.key,
      );

      expect(
        find.byKey(ValueKey('gpu-vendor-${vendor.value}')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('privileged deactivation actions are visibly unavailable', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      width: 900,
      processes: const [
        DgpuProcess(pid: 4242, name: 'blender', usedMemoryMib: 2048),
      ],
    );

    expect(
      find.text('Privileged dGPU deactivation is not available in this build.'),
      findsOneWidget,
    );
    final killButton = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('Kill 1 processes'),
        matching: find.byType(OutlinedButton),
      ),
    );
    final restartButton = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('Restart PCI device'),
        matching: find.byType(OutlinedButton),
      ),
    );
    expect(killButton.onPressed, isNull);
    expect(restartButton.onPressed, isNull);
  });
}

Future<_MockDgpuRepository> _pumpPage(
  WidgetTester tester, {
  required double width,
  required List<DgpuProcess> processes,
  String gpuName = 'NVIDIA GeForce RTX 4060',
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
  when(() => dgpuRepository.setHybridMode(any())).thenAnswer((_) async {});
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
  ).thenAnswer((_) async => _liveSensorSnapshot(gpuName));
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
      key: UniqueKey(),
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
  return dgpuRepository;
}

LiveSensorSnapshot _liveSensorSnapshot(String gpuName) => LiveSensorSnapshot(
  cpuName: 'Test CPU',
  cpuTempC: 62,
  cpuUtilPercent: 18,
  cpuClockGhz: 3.1,
  cpuPackagePowerW: 24,
  fan1Rpm: null,
  fan2Rpm: null,
  gpuName: gpuName,
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
