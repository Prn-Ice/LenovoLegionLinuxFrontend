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
import 'package:legion_frontend/features/dgpu/models/graphics_mode.dart';
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
    expect(find.text('Selected policy'), findsOneWidget);
    expect(find.text('Effective dGPU'), findsOneWidget);
    expect(find.text('Expected dGPU'), findsOneWidget);
    expect(find.text('Reconciliation'), findsOneWidget);
    expect(find.text('Settled'), findsNWidgets(2));
    expect(find.textContaining('Hybrid iGPU-only'), findsNWidgets(2));
    expect(find.textContaining('Hybrid Auto'), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey('set-graphics-hybrid-igpu-only')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('set-graphics-discrete')), findsOneWidget);
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

  testWidgets(
    'Hybrid Auto is reported with safety guidance and no Auto action',
    (tester) async {
      await _pumpPage(
        tester,
        width: 900,
        processes: const [],
        graphicsModeStatus: _autoStatus,
      );

      final graphicsCard = find.byKey(const ValueKey('graphics-mode-status'));
      await tester.ensureVisible(graphicsCard);
      expect(
        find.textContaining(
          'Hybrid Auto can eject the dGPU after AC is unplugged',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('set-graphics-hybrid-auto')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('set-graphics-hybrid')), findsOneWidget);
    },
  );

  testWidgets('graphics changes require confirmation before dispatch', (
    tester,
  ) async {
    final repository = await _pumpPage(tester, width: 900, processes: const []);

    final action = find.byKey(const ValueKey('set-graphics-hybrid-igpu-only'));
    await tester.ensureVisible(action);
    await tester.tap(action);
    await tester.pumpAndSettle();

    expect(find.text('Switch to Hybrid iGPU-only'), findsOneWidget);
    expect(find.textContaining('Disconnect external displays'), findsOneWidget);
    verifyNever(() => repository.setGraphicsMode(GraphicsMode.hybridIgpuOnly));

    await tester.tap(find.widgetWithText(FilledButton, 'Switch mode'));
    await tester.pumpAndSettle();
    verify(
      () => repository.setGraphicsMode(GraphicsMode.hybridIgpuOnly),
    ).called(1);
  });

  testWidgets('graphics status stays visible when NVIDIA is detached', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      width: 420,
      processes: const [],
      dgpuAvailable: false,
      graphicsModeStatus: _igpuOnlyStatus,
    );

    expect(find.text('Graphics mode'), findsOneWidget);
    expect(find.text('Hybrid iGPU-only'), findsNWidgets(2));
    expect(find.text('Detached'), findsNWidgets(2));
    expect(find.text('Discrete GPU detached'), findsOneWidget);
    expect(find.text('GPU unavailable'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('graphics controls fail closed without authoritative status', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      width: 420,
      processes: const [],
      graphicsModeStatus: null,
    );

    expect(
      find.textContaining(
        'Authoritative combined graphics status is unavailable',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('set-graphics-hybrid')), findsNothing);
    expect(
      find.byKey(const ValueKey('set-graphics-hybrid-igpu-only')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('set-graphics-discrete')), findsNothing);
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
  bool dgpuAvailable = true,
  GraphicsModeStatus? graphicsModeStatus = _hybridStatus,
}) async {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final dgpuRepository = _MockDgpuRepository();
  when(dgpuRepository.loadSnapshot).thenAnswer(
    (_) async => DgpuSnapshot(
      isActive: dgpuAvailable ? true : null,
      processes: processes,
      pciAddress: dgpuAvailable ? '0000:01:00.0' : null,
      graphicsModeStatus: graphicsModeStatus,
      name: 'NVIDIA Corporation AD107M',
    ),
  );
  when(dgpuRepository.loadSnapshotAfterGraphicsWrite).thenAnswer(
    (_) async => DgpuSnapshot(
      isActive: dgpuAvailable ? true : null,
      processes: processes,
      pciAddress: dgpuAvailable ? '0000:01:00.0' : null,
      graphicsModeStatus: graphicsModeStatus,
      name: 'NVIDIA Corporation AD107M',
    ),
  );
  for (final mode in const [
    GraphicsMode.hybrid,
    GraphicsMode.hybridIgpuOnly,
    GraphicsMode.discrete,
  ]) {
    when(() => dgpuRepository.setGraphicsMode(mode)).thenAnswer((_) async {});
  }
  final dgpuBloc = DgpuBloc(
    repository: dgpuRepository,
    pollInterval: const Duration(days: 1),
  );
  final dgpuLoaded = dgpuBloc.stream.firstWhere(
    (state) => !state.isLoading && state.hasLoaded,
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

const _hybridStatus = GraphicsModeStatus(
  selectedMode: GraphicsMode.hybrid,
  effectiveState: DgpuTopology.attached,
  expectedState: DgpuTopology.attached,
  reconciliation: GraphicsReconciliation.settled,
  clientInspectionComplete: false,
  activeClients: [],
  availableModes: GraphicsMode.values,
  reconciliationAttempts: null,
);

const _autoStatus = GraphicsModeStatus(
  selectedMode: GraphicsMode.hybridAuto,
  effectiveState: DgpuTopology.attached,
  expectedState: DgpuTopology.attached,
  reconciliation: GraphicsReconciliation.settled,
  clientInspectionComplete: false,
  activeClients: [],
  availableModes: GraphicsMode.values,
  reconciliationAttempts: null,
);

const _igpuOnlyStatus = GraphicsModeStatus(
  selectedMode: GraphicsMode.hybridIgpuOnly,
  effectiveState: DgpuTopology.detached,
  expectedState: DgpuTopology.detached,
  reconciliation: GraphicsReconciliation.settled,
  clientInspectionComplete: false,
  activeClients: [],
  availableModes: GraphicsMode.values,
  reconciliationAttempts: null,
);
