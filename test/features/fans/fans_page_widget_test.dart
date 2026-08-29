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
    expect(find.text('Fan curve'), findsOneWidget);
    expect(find.text('Silent'), findsOneWidget);
    expect(find.text('Aggressive'), findsOneWidget);
    expect(find.text('Current CPU fan'), findsOneWidget);
  });

  testWidgets('full page has no overflow at wide width', (tester) async {
    await _pumpPage(tester, width: 1100, dark: true);

    expect(tester.takeException(), isNull);
    expect(find.text('Balanced profile | AC power'), findsOneWidget);
    expect(find.text('CPU fan'), findsWidgets);
    expect(find.text('GPU fan'), findsWidgets);
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

      expect(find.text('Unavailable'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
      expect(find.text('Temperature unavailable'), findsOneWidget);
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

    expect(
      find.text('Balanced profile | Power source unavailable'),
      findsOneWidget,
    );
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

  testWidgets('fan workspace consistently uses the Custom accent', (
    tester,
  ) async {
    await _pumpPage(tester, width: 800);

    final editor = tester.widget<FanCurveEditor>(find.byType(FanCurveEditor));
    expect(editor.accent, LegionAccent.custom.color);
  });

  testWidgets('missing controller keeps a useful curve workspace', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      width: 1100,
      snapshot: _fansSnapshot(curveAvailable: false),
    );

    expect(find.text('Curve controls unavailable'), findsOneWidget);
    expect(find.text('64°C'), findsWidgets);
    expect(find.text('2180'), findsOneWidget);
    expect(find.text('Silent'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
  fan1Rpm: 2180,
  fan2Rpm: 1940,
  gpuName: 'Test GPU',
  gpuTempC: 58,
  gpuUtilPercent: 20,
  gpuClockGhz: 1.8,
  gpuVramUsedGb: 2,
  gpuVramTotalGb: 8,
  gpuFanRpm: null,
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
