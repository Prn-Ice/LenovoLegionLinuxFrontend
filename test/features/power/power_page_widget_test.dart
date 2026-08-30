import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/models/cpu_policy_snapshot.dart';
import 'package:legion_frontend/features/power/bloc/power_bloc.dart';
import 'package:legion_frontend/features/power/bloc/power_event.dart';
import 'package:legion_frontend/core/models/power_profiles_daemon_snapshot.dart';
import 'package:legion_frontend/features/power/models/power_limit.dart';
import 'package:legion_frontend/features/power/models/power_mode.dart';
import 'package:legion_frontend/features/power/models/power_snapshot.dart';
import 'package:legion_frontend/features/power/providers/power_provider.dart';
import 'package:legion_frontend/features/power/repository/power_repository.dart';
import 'package:legion_frontend/features/power/view/power_page.dart';
import 'package:legion_frontend/features/sensors/bloc/live_sensor_bloc.dart';
import 'package:legion_frontend/features/sensors/bloc/live_sensor_event.dart';
import 'package:legion_frontend/features/sensors/models/live_sensor_snapshot.dart';
import 'package:legion_frontend/features/sensors/providers/live_sensor_provider.dart';
import 'package:legion_frontend/features/sensors/repository/live_sensor_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:yaru/yaru.dart';

class _MockPowerRepository extends Mock implements PowerRepository {}

class _MockLiveSensorRepository extends Mock implements LiveSensorRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(const PowerMode('test'));
    registerFallbackValue(PowerRepository.allPowerLimits.first);
    registerFallbackValue(<PowerLimitReading>[]);
  });

  testWidgets('Power page follows the handoff at compact width', (
    tester,
  ) async {
    await _pumpPage(tester, width: 320);

    expect(find.text('Power'), findsNothing);
    expect(find.text('Quiet'), findsOneWidget);
    expect(find.text('Balanced'), findsWidgets);
    expect(find.text('Performance'), findsOneWidget);
    expect(find.text('Custom'), findsOneWidget);
    expect(find.text('Silent and cool'), findsNothing);
    expect(find.byKey(const ValueKey('power-limits-card')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('power-limit-slider-cpu_longterm')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('power-limit-default-cpu_longterm')),
          )
          .data,
      '54 W',
    );
    expect(find.text('Additional limits'), findsOneWidget);
    expect(find.text('CPU overclock'), findsOneWidget);
    expect(find.text('GPU overclock'), findsNothing);
    expect(find.text('Admin privileges required'), findsNothing);
    expect(find.text('Refresh'), findsNothing);

    final additionalLimits = find.text('Additional limits');
    await tester.ensureVisible(additionalLimits);
    await tester.pumpAndSettle();
    await tester.tap(additionalLimits);
    await tester.pumpAndSettle();
    expect(find.text('CPU temperature limit'), findsOneWidget);
    expect(find.text('GPU AC power-target offset'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Power page has no overflow at wide dark layout', (tester) async {
    await _pumpPage(tester, width: 1100, dark: true);

    expect(tester.takeException(), isNull);
    expect(
      tester.getTopLeft(find.text('Quiet')).dy,
      tester.getTopLeft(find.text('Custom')).dy,
    );
    final quietControl = find.ancestor(
      of: find.text('Quiet'),
      matching: find.byType(ChoiceChip),
    );
    final performanceControl = find.ancestor(
      of: find.text('Performance'),
      matching: find.byType(ChoiceChip),
    );
    expect(
      tester.getSize(quietControl.first).width,
      lessThan(tester.getSize(performanceControl.first).width),
    );
    expect(
      find.text('Quick when you need it, calm when you do not.'),
      findsOneWidget,
    );
    expect(find.byType(Slider), findsNWidgets(3));
  });

  testWidgets('unsupported tuning renders a compact truthful state', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      width: 800,
      snapshot: const PowerSnapshot(
        currentMode: PowerMode('balanced'),
        availableModes: [PowerMode('balanced')],
        powerLimits: [],
        cpuOverclockEnabled: null,
        gpuOverclockEnabled: null,
      ),
    );

    expect(
      find.text(
        'The platform controller did not provide usable power-limit values.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('overclocking-card')), findsNothing);
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('mode chip applies the matching platform profile', (
    tester,
  ) async {
    final harness = await _pumpPage(tester, width: 800);

    await tester.tap(find.text('Performance'));
    await tester.pumpAndSettle();

    verify(
      () => harness.repository.setPowerMode(const PowerMode('performance')),
    ).called(1);
  });

  testWidgets('power sliders stage changes before applying them together', (
    tester,
  ) async {
    final harness = await _pumpPage(
      tester,
      width: 800,
      snapshot: _snapshot(currentMode: const PowerMode('custom')),
    );
    final slider = find.byKey(
      const ValueKey('power-limit-slider-cpu_longterm'),
    );

    await tester.drag(slider, const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved limit changes'), findsOneWidget);

    await tester.tap(find.text('Apply changes').first);
    await tester.pumpAndSettle();

    final captured =
        verify(
              () => harness.repository.setPowerLimits(captureAny()),
            ).captured.single
            as List<PowerLimitReading>;
    expect(captured.single.value, greaterThan(55));
  });

  testWidgets('power limits explain Custom and AC prerequisites', (
    tester,
  ) async {
    await _pumpPage(tester, width: 800);

    expect(
      find.text('Switch to Custom mode to edit controller power limits.'),
      findsOneWidget,
    );
    expect(tester.widget<Slider>(find.byType(Slider).first).onChanged, isNull);
  });

  testWidgets('controller-only limits show values and hardware defaults', (
    tester,
  ) async {
    await _pumpPage(tester, width: 800);

    await tester.tap(find.text('Additional limits'));
    await tester.pumpAndSettle();

    expect(find.text('CPU temperature limit'), findsOneWidget);
    expect(find.text('100 °C'), findsWidgets);
    expect(find.text('GPU AC power-target offset'), findsOneWidget);
    expect(find.text('45 W'), findsWidgets);
    expect(find.text('Adjustable'), findsOneWidget);
    expect(find.text('Controller readings'), findsOneWidget);
    expect(find.text('Read only'), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('power-limit-default-cpu_temperature')),
          )
          .data,
      '100 °C',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(
              const ValueKey('power-limit-default-gpu_power_target_offset'),
            ),
          )
          .data,
      '45 W',
    );
    expect(find.text('Change'), findsNothing);
    expect(find.text('No staged changes'), findsNothing);
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('CPU temperature limit'),
          matching: find.byType(YaruListTile),
        ),
        matching: find.text('Change'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('GPU AC power-target offset'),
          matching: find.byType(YaruListTile),
        ),
        matching: find.text('Change'),
      ),
      findsNothing,
    );
  });

  testWidgets('compact additional limit changes stage without clutter', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      width: 320,
      snapshot: _snapshot(currentMode: const PowerMode('custom')),
    );

    final additionalLimits = find.text('Additional limits');
    await tester.ensureVisible(additionalLimits);
    await tester.pumpAndSettle();
    await tester.tap(additionalLimits);
    await tester.pumpAndSettle();

    final change = find.text('Change');
    await tester.ensureVisible(change);
    await tester.pumpAndSettle();
    await tester.tap(change);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('GPU Temperature Limit'),
      ),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), '90');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Unsaved limit changes'), findsOneWidget);
    expect(find.text('No staged changes'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unknown hardware keeps the default baseline truthful', (
    tester,
  ) async {
    final limit = PowerLimitReading(
      spec: PowerRepository.allPowerLimits.first,
      value: 55,
    );
    await _pumpPage(
      tester,
      width: 800,
      snapshot: PowerSnapshot(
        currentMode: const PowerMode('balanced'),
        availableModes: const [PowerMode('balanced')],
        powerLimits: [limit],
        cpuOverclockEnabled: null,
        gpuOverclockEnabled: null,
      ),
    );

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('power-limit-default-cpu_longterm')),
          )
          .data,
      'Unavailable',
    );
  });

  testWidgets('custom power limits remain disabled on battery', (tester) async {
    await _pumpPage(
      tester,
      width: 800,
      snapshot: _snapshot(
        currentMode: const PowerMode('custom'),
        onPowerSupply: false,
      ),
    );

    expect(
      find.text('Connect AC power to edit custom power limits.'),
      findsOneWidget,
    );
    expect(tester.widget<Slider>(find.byType(Slider).first).onChanged, isNull);
  });

  testWidgets('shows effective CPU policy without redundant status copy', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      width: 800,
      snapshot: _snapshot(
        daemonSnapshot: _daemonSnapshot,
        cpuPolicy: _cpuPolicy,
      ),
    );

    expect(find.text('CPU policy details'), findsOneWidget);
    expect(find.text('System power management active'), findsNothing);
    expect(find.text('On AC power'), findsNothing);

    expect(find.text('PPD 0.30'), findsOneWidget);
    expect(find.text('amd-pstate-epp (active)'), findsOneWidget);
    expect(find.text('platform_profile'), findsOneWidget);
    expect(find.text('powersave'), findsOneWidget);
    expect(find.text('balance_performance'), findsOneWidget);
    expect(find.text('420-3800 MHz'), findsOneWidget);
    expect(find.text('3.10 GHz'), findsOneWidget);
    expect(find.text('24.5 W'), findsOneWidget);
  });

  testWidgets('live CPU facts show a truthful unavailable state', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      width: 800,
      sensorSnapshot: LiveSensorSnapshot.initial(),
    );

    expect(find.text('Average clock'), findsOneWidget);
    expect(find.text('CPU package power'), findsOneWidget);
    expect(find.text('Unavailable'), findsNWidgets(2));
  });

  testWidgets('CPU overclock confirmation uses focused Yaru warning copy', (
    tester,
  ) async {
    final harness = await _pumpPage(tester, width: 800);

    expect(
      find.text(
        'Overclocking can increase temperature, power use, and instability.',
      ),
      findsNothing,
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('cpu-overclock')),
        matching: find.byType(YaruSwitch),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Enable CPU overclock'), findsOneWidget);
    expect(find.byType(YaruDialogTitleBar), findsOneWidget);
    expect(
      tester.getSize(find.byType(YaruDialogTitleBar)).width,
      lessThanOrEqualTo(460),
    );
    expect(
      find.text(
        'CPU overclocking can increase heat, power use, and instability. '
        'This change requires privileged access.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'GPU overclocking can increase heat, power use, and instability. '
        'This change requires privileged access.',
      ),
      findsNothing,
    );

    await tester.tap(find.text('Enable'));
    await tester.pumpAndSettle();
    verify(() => harness.repository.setCpuOverclock(true)).called(1);
  });

  testWidgets('GPU overclock confirmation uses GPU warning copy', (
    tester,
  ) async {
    final harness = await _pumpPage(
      tester,
      width: 800,
      snapshot: _snapshot(gpuOverclockSupported: true),
    );

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('gpu-overclock')),
        matching: find.byType(YaruSwitch),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Enable GPU overclock'), findsOneWidget);
    expect(
      find.text(
        'GPU overclocking can increase heat, power use, and instability. '
        'This change requires privileged access.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'CPU overclocking can increase heat, power use, and instability. '
        'This change requires privileged access.',
      ),
      findsNothing,
    );

    await tester.tap(find.text('Enable'));
    await tester.pumpAndSettle();
    verify(() => harness.repository.setGpuOverclock(true)).called(1);
  });
}

Future<_PowerHarness> _pumpPage(
  WidgetTester tester, {
  required double width,
  bool dark = false,
  PowerSnapshot? snapshot,
  LiveSensorSnapshot? sensorSnapshot,
}) async {
  tester.view.physicalSize = Size(width, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final repository = _MockPowerRepository();
  final resolvedSnapshot = snapshot ?? _snapshot();
  when(repository.loadSnapshot).thenAnswer((_) async => resolvedSnapshot);
  when(() => repository.setPowerMode(any())).thenAnswer((_) async {});
  when(() => repository.setPowerLimit(any(), any())).thenAnswer((_) async {});
  when(() => repository.setPowerLimits(any())).thenAnswer((_) async {});
  when(() => repository.setCpuOverclock(any())).thenAnswer((_) async {});
  when(() => repository.setGpuOverclock(any())).thenAnswer((_) async {});
  final sensorRepository = _MockLiveSensorRepository();
  final resolvedSensorSnapshot = sensorSnapshot ?? _liveSensorSnapshot;
  when(
    () => sensorRepository.loadSnapshot(),
  ).thenAnswer((_) async => resolvedSensorSnapshot);

  final bloc = PowerBloc(
    repository: repository,
    pollInterval: const Duration(days: 1),
  );
  final loaded = bloc.stream.firstWhere((state) => !state.isLoading);
  bloc.add(const PowerStarted());
  await loaded;

  final sensorBloc = LiveSensorBloc(
    repository: sensorRepository,
    pollInterval: const Duration(days: 1),
  );
  final sensorsLoaded = sensorBloc.stream.firstWhere(
    (state) => !state.isLoading,
  );
  sensorBloc.add(const LiveSensorStarted());
  await sensorsLoaded;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        powerBlocProvider.overrideWith((ref) => bloc),
        liveSensorBlocProvider.overrideWith((ref) => sensorBloc),
      ],
      child: YaruTheme(
        data: const YaruThemeData(),
        builder: (context, yaru, child) => MaterialApp(
          theme: yaru.theme,
          darkTheme: yaru.darkTheme,
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          home: const Scaffold(body: PowerPage()),
        ),
      ),
    ),
  );
  await tester.pump();

  return _PowerHarness(repository: repository);
}

PowerSnapshot _snapshot({
  PowerMode currentMode = const PowerMode('balanced'),
  bool? onPowerSupply = true,
  bool gpuOverclockSupported = false,
  PowerProfilesDaemonSnapshot? daemonSnapshot,
  CpuPolicySnapshot? cpuPolicy,
}) {
  PowerLimitReading reading(String id, int value, int hardwareDefault) =>
      PowerLimitReading(
        spec: PowerRepository.allPowerLimits.firstWhere(
          (spec) => spec.id == id,
        ),
        value: value,
        hardwareDefault: hardwareDefault,
      );

  return PowerSnapshot(
    currentMode: currentMode,
    availableModes: const [
      PowerMode('quiet'),
      PowerMode('balanced'),
      PowerMode('performance'),
      PowerMode('balanced-performance'),
    ],
    powerLimits: [
      reading('cpu_longterm', 55, 54),
      reading('cpu_shortterm', 75, 54),
      reading('gpu_ctgp', 140, 60),
      reading('cpu_temperature', 100, 100),
      reading('gpu_temperature', 87, 87),
      reading('gpu_power_target_offset', 45, 45),
    ],
    cpuOverclockEnabled: false,
    gpuOverclockEnabled: gpuOverclockSupported ? false : null,
    onPowerSupply: onPowerSupply,
    daemonSnapshot: daemonSnapshot,
    cpuPolicy: cpuPolicy,
  );
}

const _daemonSnapshot = PowerProfilesDaemonSnapshot(
  activeProfile: 'balanced',
  profiles: [
    PowerProfileDescriptor(
      profile: 'balanced',
      cpuDriver: 'amd_pstate',
      platformDriver: 'platform_profile',
    ),
  ],
  batteryAware: true,
  version: '0.30',
  performanceDegraded: '',
);

const _cpuPolicy = CpuPolicySnapshot(
  driver: 'amd-pstate-epp',
  pstateStatus: 'active',
  governor: 'powersave',
  energyPerformancePreference: 'balance_performance',
  boostEnabled: true,
  minimumFrequencyKhz: 420000,
  maximumFrequencyKhz: 3800000,
);

const _liveSensorSnapshot = LiveSensorSnapshot(
  cpuName: 'Test CPU',
  cpuTempC: 62,
  cpuUtilPercent: 18,
  cpuClockGhz: 3.1,
  cpuPackagePowerW: 24.5,
  fan1Rpm: null,
  fan2Rpm: null,
  gpuName: null,
  gpuTempC: null,
  gpuUtilPercent: null,
  gpuClockGhz: null,
  gpuVramUsedGb: null,
  gpuVramTotalGb: null,
  gpuFanPercent: null,
  gpuPowerDrawW: null,
  gpuIsDiscrete: false,
  motherboardTempC: null,
  batteryPercent: null,
  batteryCharging: null,
  batteryPowerDrawW: null,
  diskTempC: null,
);

class _PowerHarness {
  const _PowerHarness({required this.repository});

  final _MockPowerRepository repository;
}
