import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/models/gpu_process.dart';
import 'package:legion_frontend/core/models/gpu_process_scan.dart';
import 'package:legion_frontend/core/models/gpu_reading.dart';
import 'package:legion_frontend/features/analytics/bloc/analytics_bloc.dart';
import 'package:legion_frontend/features/analytics/models/sensor_record.dart';
import 'package:legion_frontend/features/analytics/providers/analytics_provider.dart';
import 'package:legion_frontend/features/analytics/repository/analytics_repository.dart';
import 'package:legion_frontend/features/analytics/view/widgets/telemetry_history_card.dart';
import 'package:legion_frontend/features/dgpu/bloc/dgpu_bloc.dart';
import 'package:legion_frontend/features/dgpu/bloc/dgpu_event.dart';
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
  testWidgets('GPU shows graphics mode while checking for open devices', (
    tester,
  ) async {
    final pendingProcesses = Completer<GpuProcessScan?>();
    await _pumpPage(
      tester,
      width: 420,
      processes: null,
      pendingProcesses: pendingProcesses.future,
    );
    expect(find.byType(YaruCircularProgressIndicator), findsNothing);
    expect(find.text('Selected mode'), findsOneWidget);
    expect(find.text('NVIDIA GeForce RTX 4060'), findsOneWidget);
    expect(find.text('Checking for open NVIDIA devices…'), findsOneWidget);
    expect(find.text('GPU process list unavailable.'), findsNothing);

    pendingProcesses.complete(GpuProcessScan.noClients);
    await tester.pumpAndSettle();

    expect(find.text('Checking for open NVIDIA devices…'), findsNothing);
    expect(
      find.text('No visible processes have NVIDIA devices open.'),
      findsOneWidget,
    );
  });

  testWidgets('GPU shows readings while graphics mode is pending', (
    tester,
  ) async {
    final pendingMode = Completer<GraphicsModeStatus?>();
    await _pumpPage(
      tester,
      width: 420,
      processes: const [],
      pendingMode: pendingMode.future,
    );

    expect(find.text('NVIDIA GeForce RTX 4060'), findsOneWidget);
    expect(find.text('P2'), findsOneWidget);
    expect(find.text('Checking graphics mode…'), findsOneWidget);
    expect(find.text('Selected mode'), findsNothing);

    pendingMode.complete(_hybridStatus);
    await tester.pumpAndSettle();

    expect(find.text('P2'), findsOneWidget);
    expect(find.text('Checking graphics mode…'), findsNothing);
    expect(find.text('Selected mode'), findsOneWidget);
  });

  testWidgets('GPU shows graphics controls before live readings arrive', (
    tester,
  ) async {
    final pendingSensors = Completer<LiveSensorSnapshot>();
    await _pumpPage(
      tester,
      width: 420,
      processes: const [],
      pendingSensors: pendingSensors.future,
    );

    expect(find.byType(YaruCircularProgressIndicator), findsNothing);
    expect(find.text('Graphics mode'), findsOneWidget);
    expect(find.text('P2'), findsNothing);
    expect(find.text('Loading live GPU readings…'), findsNothing);
    expect(
      find.textContaining('Live NVIDIA telemetry is unavailable'),
      findsNothing,
    );

    pendingSensors.complete(_liveSensorSnapshot('NVIDIA GeForce RTX 4060'));
    await tester.pumpAndSettle();

    expect(find.text('Loading live GPU readings…'), findsNothing);
    expect(find.text('P2'), findsOneWidget);
  });

  testWidgets('GPU shows graphics mode while detecting integrated graphics', (
    tester,
  ) async {
    final pendingSensors = Completer<LiveSensorSnapshot>();
    await _pumpPage(
      tester,
      width: 420,
      processes: null,
      dgpuAvailable: false,
      pendingSensors: pendingSensors.future,
    );

    expect(find.text('Graphics mode'), findsOneWidget);
    expect(find.text('Loading live GPU readings…'), findsOneWidget);

    pendingSensors.complete(
      _liveSensorSnapshot(
        'NVIDIA GeForce RTX 4060',
        dgpuReading: false,
        igpu: const GpuReading(name: 'AMD Integrated Graphics'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Loading live GPU readings…'), findsNothing);
    expect(find.text('AMD Integrated Graphics'), findsOneWidget);
  });

  testWidgets('dGPU handoff is responsive and shows live P-state', (
    tester,
  ) async {
    await _pumpPage(tester, width: 360, processes: const []);
    final accent = Theme.of(tester.element(find.byType(DgpuPage)))
        .colorScheme
        .primary;

    expect(find.text('NVIDIA GeForce RTX 4060'), findsOneWidget);
    expect(find.text('P2'), findsOneWidget);
    expect(find.text('Usage %'), findsOneWidget);
    expect(find.text('Graphics mode'), findsOneWidget);
    expect(find.text('Selected mode'), findsOneWidget);
    expect(find.text('NVIDIA GPU'), findsOneWidget);
    expect(find.text('Detected'), findsOneWidget);
    expect(find.text('Matches mode'), findsOneWidget);
    expect(find.text('Reconciliation'), findsNothing);
    expect(find.textContaining('privileged preflight'), findsNothing);
    expect(find.text(GraphicsMode.hybridIgpuOnly.description), findsOneWidget);
    expect(find.text(GraphicsMode.discrete.description), findsOneWidget);
    expect(find.textContaining('Hybrid Auto'), findsNothing);
    expect(find.textContaining('The app checks'), findsNothing);
    expect(find.textContaining('cannot check every program'), findsNothing);
    expect(
      find.byKey(const ValueKey('set-graphics-hybrid-igpu-only')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('set-graphics-discrete')), findsOneWidget);
    expect(find.text('GPU performance'), findsOneWidget);
    expect(find.text('Processes with NVIDIA devices open'), findsOneWidget);
    expect(
      find.text('No visible processes have NVIDIA devices open.'),
      findsOneWidget,
    );
    expect(find.text('Discrete GPU'), findsNothing);
    expect(find.byKey(const ValueKey('gpu-vendor-nvidia')), findsOneWidget);
    expect(
      tester
          .widget<TelemetryHistoryCard>(find.byType(TelemetryHistoryCard))
          .accentColor,
      accent,
    );
    expect(find.byType(YaruSwitch), findsOneWidget);
    for (final toggle in tester.widgetList<YaruSwitch>(
      find.byType(YaruSwitch),
    )) {
      expect(toggle.selectedColor, accent);
    }
    expect(find.text('Kill processes'), findsOneWidget);
    final killButton = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('Kill processes'),
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
        find.textContaining('Hybrid Auto is unsafe for desktop use'),
        findsOneWidget,
      );
      expect(find.text('Unsafe mode'), findsOneWidget);
      expect(find.text('Matches mode'), findsNothing);
      expect(find.textContaining('Keep the charger connected'), findsOneWidget);
      expect(
        find.textContaining('choose Hybrid/Switchable graphics in BIOS'),
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

    expect(find.text('Switch to Integrated graphics only'), findsOneWidget);
    expect(find.textContaining('Disconnect external displays'), findsOneWidget);
    verifyNever(() => repository.setGraphicsMode(GraphicsMode.hybridIgpuOnly));

    await tester.tap(find.widgetWithText(FilledButton, 'Switch mode'));
    await tester.pumpAndSettle();
    verify(() => repository.setGraphicsMode(GraphicsMode.hybridIgpuOnly))
        .called(1);
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
    expect(find.text('Integrated graphics only'), findsNWidgets(2));
    expect(find.text('Not detected'), findsOneWidget);
    expect(find.byKey(const ValueKey('nvidia-absent-card')), findsNothing);
    expect(find.textContaining('currently in use'), findsNothing);
    expect(find.text('GPU unavailable'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'iGPU-only mode shows integrated overview, history, and mode switching',
    (tester) async {
      await _pumpPage(
        tester,
        width: 420,
        height: 500,
        processes: const [],
        dgpuAvailable: false,
        graphicsModeStatus: _igpuOnlyStatus,
        igpu: const GpuReading(
          name: 'AMD Radeon 780M',
          usagePercent: 12,
          tempC: 55,
          clockGhz: 1.2,
          powerDrawW: 8,
        ),
      );

      expect(
        find.byKey(const ValueKey('graphics-mode-status')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('integrated-gpu-card')), findsOneWidget);
      expect(find.text('AMD Radeon 780M'), findsOneWidget);
      expect(find.byKey(const ValueKey('gpu-vendor-amd')), findsOneWidget);
      expect(find.text('12 %'), findsOneWidget);
      expect(find.text('55 °'), findsOneWidget);
      expect(find.text('1.20 GHz'), findsOneWidget);
      expect(find.text('8.0 W'), findsOneWidget);
      expect(find.byType(TelemetryHistoryCard), findsOneWidget);
      expect(find.byKey(const ValueKey('nvidia-absent-card')), findsNothing);
      expect(find.text('GPU overclock'), findsNothing);
      expect(find.text('Processes with NVIDIA devices open'), findsNothing);
      expect(find.text('Processes on the integrated GPU'), findsOneWidget);
      expect(find.text('Unavailable'), findsOneWidget);
      expect(
        find.textContaining(
          'Process usage for the integrated GPU is unavailable',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Failed to read sensors'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('switcher shows one GPU card and its own history and processes', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      width: 900,
      processes: const [
        GpuProcess(
          pid: 2182,
          name: 'kwin_wayland',
          devices: ['/dev/dri/card0'],
        ),
        GpuProcess(
          pid: 4242,
          name: 'blender',
          devices: ['/dev/dri/renderD128', '/dev/nvidia0'],
        ),
      ],
      igpu: const GpuReading(
        name: 'AMD Radeon 780M',
        usagePercent: 9,
        tempC: 51,
      ),
      igpuProcesses: const GpuProcessScan(
        processes: [GpuProcess(pid: 77, name: 'browser', usedMemoryMib: 96)],
        reporting: GpuProcessReporting.reported,
      ),
    );

    expect(find.byKey(const ValueKey('gpu-channel-toggle')), findsOneWidget);
    expect(find.text('NVIDIA GeForce RTX 4060'), findsOneWidget);
    expect(find.byKey(const ValueKey('integrated-gpu-card')), findsNothing);
    expect(find.text('Processes with NVIDIA devices open'), findsOneWidget);
    expect(find.text('kwin_wayland'), findsOneWidget);
    expect(find.text('Display (card0)'), findsOneWidget);
    expect(find.text('blender'), findsOneWidget);
    expect(
      find.text('Render (renderD128), NVIDIA driver (nvidia0)'),
      findsOneWidget,
    );
    expect(find.text('PID 4242'), findsOneWidget);
    expect(find.text('GPU overclock'), findsOneWidget);

    expect(
      tester
          .widget<TelemetryHistoryCard>(
            find.byKey(const ValueKey('gpu-history-discrete')),
          )
          .options
          .map((option) => option.label),
      ['Usage %', 'Temperature', 'Power draw'],
    );

    await tester.tap(find.text('Integrated GPU'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('integrated-gpu-card')), findsOneWidget);
    expect(find.text('AMD Radeon 780M'), findsOneWidget);
    expect(find.text('NVIDIA GeForce RTX 4060'), findsNothing);
    expect(find.text('9 %'), findsOneWidget);
    expect(find.text('51 °'), findsOneWidget);
    expect(find.text('Processes on the integrated GPU'), findsOneWidget);
    expect(find.text('browser'), findsOneWidget);
    expect(find.text('PID 77'), findsOneWidget);
    expect(find.text('96 MiB'), findsOneWidget);
    expect(find.text('blender'), findsNothing);
    expect(find.text('GPU overclock'), findsNothing);
    expect(find.text('Discrete GPU'), findsOneWidget);
    expect(
      tester
          .widget<TelemetryHistoryCard>(
            find.byKey(const ValueKey('gpu-history-integrated')),
          )
          .options
          .map((option) => option.label),
      ['Usage %', 'Temperature'],
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a suspended discrete GPU is tagged Inactive', (tester) async {
    await _pumpPage(tester, width: 900, processes: const [], dgpuActive: false);

    expect(find.text('Inactive'), findsOneWidget);
    expect(find.text('Active'), findsNothing);
    expect(
      find.textContaining('Live NVIDIA telemetry is unavailable'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'integrated process card explains when the kernel omits GPU attribution',
    (tester) async {
      await _pumpPage(
        tester,
        width: 420,
        height: 900,
        processes: const [],
        dgpuAvailable: false,
        igpu: const GpuReading(
          name: 'AMD Radeon 780M',
          usagePercent: 4,
          tempC: 45,
        ),
        igpuProcesses: GpuProcessScan.notReported,
      );

      expect(find.text('Processes on the integrated GPU'), findsOneWidget);
      expect(find.text('Unavailable'), findsOneWidget);
      expect(find.textContaining('kernel does not report'), findsOneWidget);
      expect(find.text('None found'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('GPU switcher fits with enlarged text', (tester) async {
    await _pumpPage(
      tester,
      width: 420,
      height: 500,
      textScale: 2,
      processes: const [],
      igpu: const GpuReading(
        name: 'AMD Radeon 780M',
        usagePercent: 4,
        tempC: 45,
      ),
    );

    expect(find.byKey(const ValueKey('gpu-channel-toggle')), findsOneWidget);
    final integrated = find.text('Integrated GPU');
    await tester.ensureVisible(integrated);
    await tester.tap(integrated);
    await tester.pumpAndSettle();

    expect(find.text('AMD Radeon 780M'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing NVIDIA and integrated GPUs still keep graphics mode', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      width: 420,
      height: 500,
      processes: const [],
      dgpuAvailable: false,
    );

    expect(find.byKey(const ValueKey('graphics-mode-status')), findsOneWidget);
    expect(find.byKey(const ValueKey('integrated-gpu-card')), findsNothing);
    expect(find.byKey(const ValueKey('nvidia-absent-card')), findsNothing);
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
      find.textContaining('Use Refresh to reload it before changing modes'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('set-graphics-hybrid')), findsNothing);
    expect(
      find.byKey(const ValueKey('set-graphics-hybrid-igpu-only')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('set-graphics-discrete')), findsNothing);
  });

  testWidgets('graphics details are secondary and can be opened', (
    tester,
  ) async {
    await _pumpPage(tester, width: 420, height: 500, processes: const []);
    final details = find.text('Graphics details');
    await tester.ensureVisible(details);
    await tester.pumpAndSettle();
    expect(
      find.text('Expected NVIDIA GPU: Detected').hitTestable(),
      findsNothing,
    );
    await tester.tap(details);
    await tester.pumpAndSettle();
    final expected = find.text('Expected NVIDIA GPU: Detected');
    await tester.ensureVisible(expected);
    await tester.pumpAndSettle();
    expect(expected.hitTestable(), findsOneWidget);
    expect(find.textContaining('cannot check every program'), findsNothing);
    expect(find.textContaining('Hybrid Auto'), findsNothing);
    expect(find.textContaining('Supported choices:'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final reconciliation in [
    GraphicsReconciliation.needed,
    GraphicsReconciliation.blocked,
    GraphicsReconciliation.unknown,
  ]) {
    testWidgets(
      'graphics status gives a recovery action (${reconciliation.name})',
      (tester) async {
        await _pumpPage(
          tester,
          width: 420,
          processes: const [],
          graphicsModeStatus: GraphicsModeStatus(
            selectedMode: GraphicsMode.hybridIgpuOnly,
            effectiveState: DgpuTopology.partial,
            expectedState: DgpuTopology.detached,
            reconciliation: reconciliation,
            clientInspectionComplete: false,
            activeClients: const [],
            availableModes: GraphicsMode.values,
            reconciliationAttempts: 1,
          ),
        );
        final recovery = switch (reconciliation) {
          GraphicsReconciliation.needed =>
            'Save your work and restart the laptop',
          GraphicsReconciliation.blocked =>
            'Close applications using NVIDIA graphics',
          _ => 'Use Refresh to reload graphics status',
        };
        expect(find.textContaining(recovery), findsOneWidget);
        expect(find.textContaining('do not assume'), findsNothing);
        expect(find.textContaining('not confirmed'), findsNothing);
        expect(find.text('Partly detected'), findsOneWidget);
        expect(find.text('Matches mode'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'NVIDIA-only confirmation explains the required restart and can be canceled',
    (tester) async {
      final repository = await _pumpPage(
        tester,
        width: 420,
        height: 500,
        processes: const [],
      );
      final action = find.byKey(const ValueKey('set-graphics-discrete'));
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.text('Switch to NVIDIA graphics only'), findsOneWidget);
      expect(find.textContaining('must restart the laptop'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      verifyNever(() => repository.setGraphicsMode(GraphicsMode.discrete));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('graphics choices fit with enlarged text', (tester) async {
    await _pumpPage(
      tester,
      width: 420,
      height: 500,
      textScale: 2,
      processes: const [],
    );
    final action = find.byKey(const ValueKey('set-graphics-hybrid-igpu-only'));
    await tester.ensureVisible(action);
    await tester.pumpAndSettle();
    expect(action.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
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
        GpuProcess(
          pid: 4242,
          name: 'blender',
          devices: ['/dev/dri/renderD128'],
        ),
      ],
    );

    expect(
      find.text('Privileged dGPU deactivation is not available in this build.'),
      findsOneWidget,
    );
    final killButton = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('Kill processes'),
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

  testWidgets('shows when NVIDIA process inspection is unavailable', (
    tester,
  ) async {
    await _pumpPage(tester, width: 420, processes: null);

    expect(find.text('GPU process list unavailable.'), findsOneWidget);
    expect(
      find.text('No visible processes have NVIDIA devices open.'),
      findsNothing,
    );
  });
}

Future<_MockDgpuRepository> _pumpPage(
  WidgetTester tester, {
  required double width,
  double height = 1400,
  double textScale = 1,
  required List<GpuProcess>? processes,
  String gpuName = 'NVIDIA GeForce RTX 4060',
  bool dgpuAvailable = true,
  bool? dgpuActive,
  GpuReading? igpu,
  GpuProcessScan? igpuProcesses,
  GraphicsModeStatus? graphicsModeStatus = _hybridStatus,
  Future<LiveSensorSnapshot>? pendingSensors,
  Future<GpuProcessScan?>? pendingProcesses,
  Future<GraphicsModeStatus?>? pendingMode,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final dgpuRepository = _MockDgpuRepository();
  final processScan = processes == null
      ? null
      : GpuProcessScan(
          processes: processes,
          reporting: processes.isEmpty
              ? GpuProcessReporting.noClients
              : GpuProcessReporting.reported,
        );
  when(() => dgpuRepository.loadProcessScan(any())).thenAnswer((_) async {
    if (pendingProcesses != null) return pendingProcesses;
    return processScan;
  });
  when(dgpuRepository.loadSnapshot).thenAnswer(
    (_) async => DgpuSnapshot(
      isActive: dgpuAvailable ? (dgpuActive ?? true) : null,
      pciAddress: dgpuAvailable ? '0000:01:00.0' : null,
    ),
  );
  when(() => dgpuRepository.loadDeviceName(any()))
      .thenAnswer((_) async => 'NVIDIA Corporation AD107M');
  when(
    () =>
        dgpuRepository.loadGraphicsModeStatus(required: any(named: 'required')),
  ).thenAnswer((_) async {
    if (pendingMode != null) return pendingMode;
    return graphicsModeStatus;
  });
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
  final dgpuLoaded = pendingMode == null
      ? dgpuBloc.stream.firstWhere(
          (state) => !state.isLoading && state.hasLoaded,
        )
      : null;
  dgpuBloc.add(const DgpuStarted());
  await dgpuLoaded;

  final sensorRepository = _MockLiveSensorRepository();
  when(() => sensorRepository.loadSnapshot(onReading: any(named: 'onReading')))
      .thenAnswer((_) async {
        if (pendingSensors != null) return pendingSensors;
        return _liveSensorSnapshot(
          gpuName,
          dgpuReading: dgpuAvailable && (dgpuActive ?? true),
          igpu: igpu,
          igpuProcesses: igpuProcesses,
        );
      });
  final sensorBloc = LiveSensorBloc(
    repository: sensorRepository,
    pollInterval: const Duration(days: 1),
  );
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
  when(() => analyticsRepository.readHistory(since: any(named: 'since')))
      .thenReturn(history);
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
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const Scaffold(body: DgpuPage()),
        ),
      ),
    ),
  );
  if (pendingSensors == null) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  return dgpuRepository;
}

LiveSensorSnapshot _liveSensorSnapshot(
  String gpuName, {
  bool dgpuReading = true,
  GpuReading? igpu,
  GpuProcessScan? igpuProcesses,
}) => LiveSensorSnapshot(
  cpuName: 'Test CPU',
  cpuTempC: 62,
  cpuUtilPercent: 18,
  cpuClockGhz: 3.1,
  cpuPackagePowerW: 24,
  fan1Rpm: null,
  fan2Rpm: null,
  igpu: igpu,
  igpuProcesses: igpuProcesses,
  dgpu: dgpuReading
      ? GpuReading(
          name: gpuName,
          tempC: 64,
          usagePercent: 42,
          clockGhz: 1.8,
          vramUsedGb: 2.1,
          vramTotalGb: 8,
          fanPercent: 35,
          powerDrawW: 38,
          performanceState: 'P2',
        )
      : null,
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
