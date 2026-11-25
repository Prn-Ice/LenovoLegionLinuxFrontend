import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/models/app_failure.dart';
import 'package:legion_frontend/core/models/gpu_reading.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:legion_frontend/core/theme/legion_accent.dart';
import 'package:legion_frontend/core/widgets/app_shell_components.dart';
import 'package:legion_frontend/features/analytics/bloc/analytics_bloc.dart';
import 'package:legion_frontend/features/analytics/models/sensor_record.dart';
import 'package:legion_frontend/features/analytics/providers/analytics_provider.dart';
import 'package:legion_frontend/features/analytics/repository/analytics_repository.dart';
import 'package:legion_frontend/features/analytics/view/widgets/telemetry_history_card.dart';
import 'package:legion_frontend/features/fans/bloc/fans_bloc.dart';
import 'package:legion_frontend/features/fans/bloc/fans_event.dart';
import 'package:legion_frontend/features/fans/models/fan_curve.dart';
import 'package:legion_frontend/features/fans/models/fans_snapshot.dart';
import 'package:legion_frontend/features/fans/providers/fans_provider.dart';
import 'package:legion_frontend/features/fans/repository/fans_repository.dart';
import 'package:legion_frontend/features/fans/view/fan_curve_editor.dart';
import 'package:legion_frontend/features/fans/view/fans_page.dart';
import 'package:legion_frontend/features/sensors/bloc/live_sensor_bloc.dart';
import 'package:legion_frontend/features/sensors/models/live_sensor_snapshot.dart';
import 'package:legion_frontend/features/sensors/providers/live_sensor_provider.dart';
import 'package:legion_frontend/features/sensors/repository/live_sensor_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:yaru/yaru.dart';

class _MockFansRepository extends Mock implements FansRepository {}

class _MockLiveSensorRepository extends Mock implements LiveSensorRepository {}

class _MockAnalyticsRepository extends Mock implements AnalyticsRepository {}

void main() {
  testWidgets(
    'speed-only firmware shows the step chart and both live fan readings',
    (tester) async {
      await _pumpPage(
        tester,
        width: 420,
        height: 500,
        snapshot: const FansSnapshot(
          platformProfile: 'balanced',
          onPowerSupply: true,
          recommendedPreset: null,
          availablePresets: ['quiet-ac'],
          miniFanCurveEnabled: null,
          lockFanControllerEnabled: null,
          maximumFanSpeedEnabled: null,
          fanCurve: FanCurve(
            name: 'firmware',
            schema: FanCurveSchema.speedOnly,
            speedUnit: FanSpeedUnit.level,
            writeStatus: FanCurveWriteStatus.unsupported,
            points: [FanCurvePoint(fan1Level: 2, fan1Rpm: 1800, fan2Rpm: 1700)],
          ),
        ),
      );
      expect(find.byKey(const ValueKey('fan-step-chart')), findsOneWidget);
      expect(find.byKey(const ValueKey('fan-speed-table')), findsNothing);
      expect(find.text('Fan speed steps'), findsOneWidget);
      expect(find.textContaining("You can't edit these yet"), findsOneWidget);
      expect(
        find.text(
          'https://github.com/johnfanv2/LenovoLegionLinux/blob/main/docs/compatible-models.md',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('fan-channel-toggle')), findsOneWidget);
      expect(find.byKey(const ValueKey('fan-preset-quiet-ac')), findsNothing);
      expect(find.byKey(const ValueKey('fan-curve-save')), findsNothing);
      expect(find.byKey(const ValueKey('fan-precise-controls')), findsNothing);
      expect(find.text('Lock fan controller'), findsNothing);
      expect(find.text('Reduce fan cycling'), findsNothing);
      expect(find.text('Current fan speeds'), findsOneWidget);
      expect(find.text('2180 RPM (44% of max)'), findsOneWidget);
      expect(find.text('1940 RPM (39% of max)'), findsOneWidget);
      expect(find.text('64°C'), findsOneWidget);
      expect(find.text('58°C'), findsOneWidget);
      expect(find.text('Step 1 of 1 (estimated)'), findsNWidgets(2));

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('fan-channel-toggle')),
          matching: find.text('GPU fan'),
        ),
      );
      await tester.pump();
      final toggle = tester.widget<ToggleButtons>(
        find.byKey(const ValueKey('fan-channel-toggle')),
      );
      expect(toggle.isSelected, [false, true]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('GPU fan temperature falls back to the integrated GPU', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      width: 420,
      height: 500,
      snapshot: _speedOnlySnapshot(),
      sensors: _sensorSnapshot(
        dgpu: null,
        igpu: const GpuReading(name: 'AMD Radeon 780M', tempC: 55),
        fan1MaxRpm: null,
        fan2MaxRpm: null,
      ),
    );

    expect(find.text('55°C'), findsOneWidget);
    expect(find.text('58°C'), findsNothing);
    expect(find.text('2180 RPM'), findsOneWidget);
    expect(find.text('1940 RPM'), findsOneWidget);
    expect(find.textContaining('% of max'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fans page offers fan and temperature history', (tester) async {
    await _pumpPage(tester, width: 800);

    final card = tester.widget<TelemetryHistoryCard>(
      find.byType(TelemetryHistoryCard),
    );
    expect(card.options.map((option) => option.label), [
      'Fan 1 RPM',
      'Fan 2 RPM',
      'CPU temperature',
      'GPU temperature',
    ]);
    expect(card.history, isNotEmpty);
  });

  testWidgets('analytics failures use the page error slot', (tester) async {
    await _pumpPage(tester, width: 800, analyticsFails: true);

    final body = tester.widget<AppPageBody>(find.byType(AppPageBody));
    final error = body.errorMessage;
    expect(error, isA<AppFailure>());
    expect((error! as AppFailure).message, contains('Sensor read failed'));
  });

  testWidgets('full page has no overflow at compact width', (tester) async {
    await _pumpPage(tester, width: 320);

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('fan-channel-toggle')), findsOneWidget);
    expect(find.text('Fan curve'), findsNothing);
    expect(find.text('Refresh'), findsNothing);
    expect(find.textContaining('profile'), findsNothing);
    expect(find.text('Silent'), findsOneWidget);
    expect(find.text('Aggressive'), findsOneWidget);
    expect(find.text('Current CPU fan speed'), findsOneWidget);
  });

  testWidgets('full page has no overflow at wide width', (tester) async {
    await _pumpPage(tester, width: 1100, dark: true);

    expect(tester.takeException(), isNull);
    final toggle = tester.widget<ToggleButtons>(
      find.byKey(const ValueKey('fan-channel-toggle')),
    );
    expect(toggle.isSelected, [true, false]);
    expect(find.text('CPU fan'), findsOneWidget);
    expect(find.text('GPU fan'), findsOneWidget);
  });

  testWidgets(
    'null capabilities and sensors are unavailable, not false or zero',
    (tester) async {
      await _pumpPage(
        tester,
        width: 800,
        snapshot: _fansSnapshot(
          maximumFanSpeedEnabled: null,
          miniFanCurveEnabled: null,
          lockFanControllerEnabled: null,
        ),
        sensors: LiveSensorSnapshot.initial(),
      );

      expect(find.text('Unavailable'), findsNothing);
      expect(find.text('—'), findsOneWidget);
      expect(find.text('Temperature unavailable'), findsOneWidget);
      expect(find.text('Fan controls'), findsNothing);
    },
  );

  testWidgets('unknown power source does not present presets as AC-only', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      width: 800,
      snapshot: _fansSnapshot(onPowerSupply: null),
    );

    expect(find.textContaining('Power source unavailable'), findsNothing);
    expect(find.text('Silent (AC)'), findsOneWidget);
    expect(find.text('Silent'), findsNothing);
  });

  testWidgets('preset selection survives canceled privilege confirmation', (
    tester,
  ) async {
    final harness = await _pumpPage(tester, width: 800);

    await tester.tap(find.text('Aggressive'));
    await tester.pumpAndSettle();
    expect(find.text('Apply Aggressive preset'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(harness.fansBloc.state.selectedPreset, 'performance-ac');
    verifyNever(() => harness.fansRepository.applyPreset(any()));
  });

  testWidgets('preset chip applies the matching context preset', (
    tester,
  ) async {
    final harness = await _pumpPage(tester, width: 800);

    await tester.tap(find.text('Balanced'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply preset'));
    await tester.pumpAndSettle();

    verify(() => harness.fansRepository.applyPreset('balanced-ac')).called(1);
  });

  testWidgets('editing a fan curve preserves the app interaction accent', (
    tester,
  ) async {
    final harness = await _pumpPage(tester, width: 800);

    var editor = tester.widget<FanCurveEditor>(find.byType(FanCurveEditor));
    final appAccent = Theme.of(tester.element(find.byType(FansPage)))
        .colorScheme
        .primary;
    expect(editor.accent, appAccent);

    final curve = harness.fansBloc.state.fanCurve!;
    harness.fansBloc.add(
      FanCurvePointUpdated(
        index: 0,
        point: curve.points.first.copyWith(fan1Rpm: 900),
      ),
    );
    await tester.pump();

    editor = tester.widget<FanCurveEditor>(find.byType(FanCurveEditor));
    expect(editor.accent, appAccent);
  });

  testWidgets('recommended preset is distinct from explicit selection', (
    tester,
  ) async {
    await _pumpPage(tester, width: 800);

    final silent = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('fan-preset-quiet-ac')),
    );
    expect(silent.selected, isFalse);
    expect(silent.avatar, isNotNull);
    expect(silent.checkmarkColor, LegionAccent.quiet.color);
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('fan-preset-performance-ac')),
          )
          .checkmarkColor,
      LegionAccent.performance.color,
    );

    await tester.tap(find.text('Balanced'));
    await tester.pump();

    final balanced = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('fan-preset-balanced-ac')),
    );
    expect(balanced.selected, isTrue);
    expect(
      balanced.selectedColor,
      Color.alphaBlend(
        LegionAccent.balanced.color.withValues(alpha: 0.2),
        Theme.of(tester.element(find.byType(FansPage))).colorScheme.surface,
      ),
    );
  });

  testWidgets('custom preset uses the Custom semantic accent', (tester) async {
    await _pumpPage(tester, width: 800);

    await tester.tap(find.text('Custom'));
    await tester.pump();

    final custom = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('fan-preset-balanced-performance-ac')),
    );
    expect(custom.selected, isTrue);
    expect(custom.checkmarkColor, LegionAccent.custom.color);
  });

  testWidgets('Yaru channel toggle switches the live fan context', (
    tester,
  ) async {
    await _pumpPage(tester, width: 800);

    await tester.tap(find.text('GPU fan'));
    await tester.pump();

    final toggle = tester.widget<ToggleButtons>(
      find.byKey(const ValueKey('fan-channel-toggle')),
    );
    expect(toggle.isSelected, [false, true]);
    expect(find.text('Current GPU fan speed'), findsOneWidget);
  });

  testWidgets('missing controller keeps a useful curve workspace', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      width: 1100,
      snapshot: _fansSnapshot(curveAvailable: false),
    );

    expect(find.text('Fan curve editing unavailable'), findsOneWidget);
    expect(
      find.textContaining('Current fan speed and temperature are shown below'),
      findsOneWidget,
    );
    expect(find.textContaining('Live reading'), findsNothing);
    expect(find.byKey(const ValueKey('fan-curve-chart-plot')), findsNothing);
    expect(find.text('64°C'), findsWidgets);
    expect(find.text('2180'), findsOneWidget);
    expect(find.text('Silent'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final readings in [(1800, null), (null, 47.0), (null, null)]) {
    testWidgets(
      'missing curve describes available measurements (${readings.$1}, ${readings.$2})',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: FanCurveUnavailablePanel(
                  channel: FanChannel.cpu,
                  currentRpm: readings.$1,
                  currentTemperature: readings.$2,
                  accent: Colors.blue,
                ),
              ),
            ),
          ),
        );
        final expected = switch (readings) {
          (null, null) => 'Fan speed and temperature are also unavailable.',
          (null, _) =>
            'Current temperature is shown below. Fan speed is unavailable.',
          (_, null) =>
            'Current fan speed is shown below. Temperature is unavailable.',
          _ => throw StateError('Unexpected fixture'),
        };
        expect(find.textContaining(expected), findsOneWidget);
        expect(find.textContaining('remain available'), findsNothing);
        expect(find.textContaining('Live reading'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('supported hardware controls use a plain Yaru settings section', (
    tester,
  ) async {
    await _pumpPage(tester, width: 800);

    expect(find.text('Fan controls'), findsOneWidget);
    expect(find.text('Reduce fan cycling'), findsOneWidget);
    expect(find.text('Maximum fan speed'), findsOneWidget);
    expect(find.text('Lock fan controller'), findsOneWidget);
    expect(find.text('Controller safeguards'), findsNothing);
    expect(find.text('Admin privileges required'), findsNothing);
  });

  testWidgets('maximum fan speed is disabled outside Custom mode when off', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      width: 800,
      snapshot: const FansSnapshot(
        platformProfile: 'balanced',
        onPowerSupply: true,
        recommendedPreset: null,
        availablePresets: [],
        miniFanCurveEnabled: null,
        lockFanControllerEnabled: null,
        maximumFanSpeedEnabled: false,
        fanCurve: null,
      ),
    );

    expect(
      find.text('Switch to Custom power mode to use maximum fan speed.'),
      findsOneWidget,
    );
    final disabledSwitch = tester.widget<YaruSwitch>(
      find.descendant(
        of: find.byKey(const ValueKey('maximum-fan-speed')),
        matching: find.byType(YaruSwitch),
      ),
    );
    expect(disabledSwitch.onChanged, isNull);
  });

  testWidgets(
    'maximum fan speed can still turn off outside Custom mode when on',
    (tester) async {
      await _pumpPage(
        tester,
        width: 800,
        snapshot: const FansSnapshot(
          platformProfile: 'balanced',
          onPowerSupply: true,
          recommendedPreset: null,
          availablePresets: [],
          miniFanCurveEnabled: null,
          lockFanControllerEnabled: null,
          maximumFanSpeedEnabled: true,
          fanCurve: null,
        ),
      );

      expect(
        find.text('Run both fans at full speed until disabled.'),
        findsOneWidget,
      );
      final enabledSwitch = tester.widget<YaruSwitch>(
        find.descendant(
          of: find.byKey(const ValueKey('maximum-fan-speed')),
          matching: find.byType(YaruSwitch),
        ),
      );
      expect(enabledSwitch.onChanged, isNotNull);
    },
  );
}

Future<_PageHarness> _pumpPage(
  WidgetTester tester, {
  required double width,
  double height = 1200,
  bool dark = false,
  bool analyticsFails = false,
  FansSnapshot? snapshot,
  LiveSensorSnapshot? sensors,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final fansRepository = _MockFansRepository();
  final sensorRepository = _MockLiveSensorRepository();
  when(fansRepository.loadSnapshot)
      .thenAnswer((_) async => snapshot ?? _fansSnapshot());
  when(() => fansRepository.applyPreset(any())).thenAnswer((_) async {});
  when(sensorRepository.loadSnapshot)
      .thenAnswer((_) async => sensors ?? _sensorSnapshot());

  final fansBloc = FansBloc(
    repository: fansRepository,
    pollInterval: const Duration(days: 1),
  );
  final sensorBloc = LiveSensorBloc(
    repository: sensorRepository,
    pollInterval: const Duration(days: 1),
  );
  final loaded = fansBloc.stream.firstWhere((state) => state.hasLoaded);
  fansBloc.add(const FansStarted());
  await loaded;

  final analyticsRepository = _MockAnalyticsRepository();
  when(analyticsRepository.pruneOldRecords).thenAnswer((_) async {});
  when(analyticsRepository.recordReading).thenAnswer((_) async {
    if (analyticsFails) throw StateError('nvidia-smi read failed');
    return _history.last;
  });
  when(() => analyticsRepository.readHistory(since: any(named: 'since')))
      .thenReturn(_history);
  final analyticsBloc = AnalyticsBloc(
    repository: analyticsRepository,
    pollInterval: const Duration(days: 1),
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fansBlocProvider.overrideWith((ref) => fansBloc),
        liveSensorBlocProvider.overrideWith((ref) => sensorBloc),
        analyticsBlocProvider.overrideWith((ref) => analyticsBloc),
      ],
      child: YaruTheme(
        data: const YaruThemeData(),
        builder: (context, yaru, child) => MaterialApp(
          theme: yaru.theme,
          darkTheme: yaru.darkTheme,
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          home: const Scaffold(body: FansPage()),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();

  return _PageHarness(
    fansBloc: fansBloc,
    fansRepository: fansRepository,
    analyticsBloc: analyticsBloc,
  );
}

FansSnapshot _fansSnapshot({
  bool? maximumFanSpeedEnabled = false,
  bool? miniFanCurveEnabled = true,
  bool? lockFanControllerEnabled = false,
  bool curveAvailable = true,
  bool? onPowerSupply = true,
}) => FansSnapshot(
  platformProfile: 'balanced',
  onPowerSupply: onPowerSupply,
  recommendedPreset: 'quiet-ac',
  availablePresets: const [
    'quiet-ac',
    'balanced-ac',
    'performance-ac',
    'balanced-performance-ac',
  ],
  miniFanCurveEnabled: miniFanCurveEnabled,
  lockFanControllerEnabled: lockFanControllerEnabled,
  maximumFanSpeedEnabled: maximumFanSpeedEnabled,
  fanCurve: curveAvailable
      ? FanCurve(
          name: 'page-test',
          fan1MaxRpm: 5000,
          fan2MaxRpm: 5000,
          points: List.generate(
            10,
            (index) => FanCurvePoint(
              fan1Rpm: 800 + index * 300,
              fan2Rpm: 900 + index * 300,
              cpuLowerTemp: 20 + index * 7,
              cpuUpperTemp: 23 + index * 7,
              gpuLowerTemp: 22 + index * 7,
              gpuUpperTemp: 26 + index * 7,
              icLowerTemp: 24 + index * 6,
              icUpperTemp: 27 + index * 6,
              accel: 5,
              decel: 7,
            ),
          ),
        )
      : null,
);

FansSnapshot _speedOnlySnapshot() => const FansSnapshot(
  platformProfile: 'balanced',
  onPowerSupply: true,
  recommendedPreset: null,
  availablePresets: ['quiet-ac'],
  miniFanCurveEnabled: null,
  lockFanControllerEnabled: null,
  maximumFanSpeedEnabled: null,
  fanCurve: FanCurve(
    name: 'firmware',
    schema: FanCurveSchema.speedOnly,
    speedUnit: FanSpeedUnit.level,
    writeStatus: FanCurveWriteStatus.unsupported,
    points: [FanCurvePoint(fan1Level: 2, fan1Rpm: 1800, fan2Rpm: 1700)],
  ),
);

LiveSensorSnapshot _sensorSnapshot({
  GpuReading? dgpu = const GpuReading(
    name: 'Test GPU',
    tempC: 58,
    usagePercent: 20,
    clockGhz: 1.8,
    vramUsedGb: 2,
    vramTotalGb: 8,
    powerDrawW: 40,
  ),
  GpuReading? igpu,
  int? fan1MaxRpm = 5000,
  int? fan2MaxRpm = 5000,
}) => LiveSensorSnapshot(
  cpuName: 'Test CPU',
  cpuTempC: 64,
  cpuUtilPercent: 35,
  cpuClockGhz: 4.1,
  cpuPackagePowerW: 24.5,
  fan1Rpm: 2180,
  fan1MaxRpm: fan1MaxRpm,
  fan2Rpm: 1940,
  fan2MaxRpm: fan2MaxRpm,
  igpu: igpu,
  dgpu: dgpu,
  motherboardTempC: 42,
  batteryPercent: 90,
  batteryCharging: true,
  batteryPowerDrawW: 0,
  diskTempC: 38,
);

final _history = [
  SensorRecord(
    timestamp: DateTime.now().subtract(const Duration(minutes: 1)),
    fan1Rpm: 2100,
    fan2Rpm: 1900,
    cpuTempC: 63,
    dgpuTempC: 57,
  ),
  SensorRecord(
    timestamp: DateTime.now(),
    fan1Rpm: 2180,
    fan2Rpm: 1940,
    cpuTempC: 64,
    dgpuTempC: 58,
  ),
];

class _PageHarness {
  const _PageHarness({
    required this.fansBloc,
    required this.fansRepository,
    required this.analyticsBloc,
  });

  final FansBloc fansBloc;
  final _MockFansRepository fansRepository;
  final AnalyticsBloc analyticsBloc;
}
