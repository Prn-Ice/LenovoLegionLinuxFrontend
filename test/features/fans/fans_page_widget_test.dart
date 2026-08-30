import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:legion_frontend/core/theme/legion_accent.dart';
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

void main() {
  testWidgets('full page has no overflow at compact width', (tester) async {
    await _pumpPage(tester, width: 320);

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('fan-channel-toggle')), findsOneWidget);
    expect(find.text('Fan curve'), findsNothing);
    expect(find.text('Refresh'), findsNothing);
    expect(find.textContaining('profile'), findsNothing);
    expect(find.text('Silent'), findsOneWidget);
    expect(find.text('Aggressive'), findsOneWidget);
    expect(find.text('Current CPU fan'), findsOneWidget);
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

  testWidgets('fan workspace follows profile until the curve is edited', (
    tester,
  ) async {
    final harness = await _pumpPage(tester, width: 800);

    var editor = tester.widget<FanCurveEditor>(find.byType(FanCurveEditor));
    expect(editor.accent, LegionAccent.balanced.color);

    final curve = harness.fansBloc.state.fanCurve!;
    harness.fansBloc.add(
      FanCurvePointUpdated(
        index: 0,
        point: curve.points.first.copyWith(fan1Rpm: 900),
      ),
    );
    await tester.pump();

    editor = tester.widget<FanCurveEditor>(find.byType(FanCurveEditor));
    expect(editor.accent, LegionAccent.custom.color);
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
    expect(find.text('Current GPU fan'), findsOneWidget);
  });

  testWidgets('missing controller keeps a useful curve workspace', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      width: 1100,
      snapshot: _fansSnapshot(curveAvailable: false),
    );

    expect(find.text('Custom curve editing is not available'), findsOneWidget);
    expect(find.byKey(const ValueKey('fan-curve-chart-plot')), findsNothing);
    expect(find.text('64°C'), findsWidgets);
    expect(find.text('2180'), findsOneWidget);
    expect(find.text('Silent'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('supported hardware controls use a plain Yaru settings section', (
    tester,
  ) async {
    await _pumpPage(tester, width: 800);

    expect(find.text('Fan controls'), findsOneWidget);
    expect(find.text('Reduce fan cycling'), findsOneWidget);
    expect(find.text('Maximum fan speed'), findsOneWidget);
    expect(find.text('Exclusive fan control'), findsOneWidget);
    expect(find.text('Controller safeguards'), findsNothing);
    expect(find.text('Admin privileges required'), findsNothing);
  });
}

Future<_PageHarness> _pumpPage(
  WidgetTester tester, {
  required double width,
  bool dark = false,
  FansSnapshot? snapshot,
  LiveSensorSnapshot? sensors,
}) async {
  tester.view.physicalSize = Size(width, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final fansRepository = _MockFansRepository();
  final sensorRepository = _MockLiveSensorRepository();
  when(
    fansRepository.loadSnapshot,
  ).thenAnswer((_) async => snapshot ?? _fansSnapshot());
  when(() => fansRepository.applyPreset(any())).thenAnswer((_) async {});
  when(
    sensorRepository.loadSnapshot,
  ).thenAnswer((_) async => sensors ?? _sensorSnapshot());

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

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fansBlocProvider.overrideWith((ref) => fansBloc),
        liveSensorBlocProvider.overrideWith((ref) => sensorBloc),
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

  return _PageHarness(fansBloc: fansBloc, fansRepository: fansRepository);
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

LiveSensorSnapshot _sensorSnapshot() => const LiveSensorSnapshot(
  cpuName: 'Test CPU',
  cpuTempC: 64,
  cpuUtilPercent: 35,
  cpuClockGhz: 4.1,
  cpuPackagePowerW: 24.5,
  fan1Rpm: 2180,
  fan2Rpm: 1940,
  gpuName: 'Test GPU',
  gpuTempC: 58,
  gpuUtilPercent: 20,
  gpuClockGhz: 1.8,
  gpuVramUsedGb: 2,
  gpuVramTotalGb: 8,
  gpuFanPercent: null,
  gpuPowerDrawW: 40,
  gpuIsDiscrete: true,
  motherboardTempC: 42,
  batteryPercent: 90,
  batteryCharging: true,
  batteryPowerDrawW: 0,
  diskTempC: 38,
);

class _PageHarness {
  const _PageHarness({required this.fansBloc, required this.fansRepository});

  final FansBloc fansBloc;
  final _MockFansRepository fansRepository;
}
