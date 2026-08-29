import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/power/bloc/power_bloc.dart';
import 'package:legion_frontend/features/power/bloc/power_event.dart';
import 'package:legion_frontend/features/power/models/power_limit.dart';
import 'package:legion_frontend/features/power/models/power_mode.dart';
import 'package:legion_frontend/features/power/models/power_snapshot.dart';
import 'package:legion_frontend/features/power/providers/power_provider.dart';
import 'package:legion_frontend/features/power/repository/power_repository.dart';
import 'package:legion_frontend/features/power/view/power_page.dart';
import 'package:mocktail/mocktail.dart';
import 'package:yaru/yaru.dart';

class _MockPowerRepository extends Mock implements PowerRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(const PowerMode('test'));
    registerFallbackValue(PowerRepository.allPowerLimits.first);
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
    expect(find.text('Additional limits (1)'), findsOneWidget);
    expect(find.text('CPU overclock'), findsOneWidget);
    expect(find.text('GPU overclock'), findsNothing);
    expect(find.text('Admin privileges required'), findsNothing);
    expect(find.text('Refresh'), findsNothing);
    final exception = tester.takeException();
    if (exception case final FlutterError error) {
      fail(error.toStringDeep());
    }
    expect(exception, isNull);
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
      matching: find.byType(InkWell),
    );
    final performanceControl = find.ancestor(
      of: find.text('Performance'),
      matching: find.byType(InkWell),
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
        'The platform controller does not expose adjustable power limits.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('overclocking-card')), findsNothing);
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('mode card applies the matching platform profile', (
    tester,
  ) async {
    final harness = await _pumpPage(tester, width: 800);

    await tester.tap(find.text('Performance'));
    await tester.pumpAndSettle();
    expect(find.text('Set Performance mode'), findsOneWidget);

    await tester.tap(find.text('Set mode'));
    await tester.pumpAndSettle();

    verify(
      () => harness.repository.setPowerMode(const PowerMode('performance')),
    ).called(1);
  });

  testWidgets('power slider confirms and writes its controller limit', (
    tester,
  ) async {
    final harness = await _pumpPage(tester, width: 800);
    final slider = find.byKey(
      const ValueKey('power-limit-slider-cpu_longterm'),
    );

    await tester.drag(slider, const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(find.text('Set CPU sustained (PL1)'), findsOneWidget);

    await tester.tap(find.text('Apply limit'));
    await tester.pumpAndSettle();

    final captured =
        verify(
              () => harness.repository.setPowerLimit(
                PowerRepository.allPowerLimits.first,
                captureAny(),
              ),
            ).captured.single
            as int;
    expect(captured, greaterThan(55));
  });

  testWidgets('supported overclock toggle keeps its adjacent warning', (
    tester,
  ) async {
    final harness = await _pumpPage(tester, width: 800);

    expect(
      find.text(
        'Overclocking can increase temperature, power use, and instability.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('CPU overclock'));
    await tester.pumpAndSettle();
    expect(find.text('Enable CPU overclock'), findsOneWidget);

    await tester.tap(find.text('Enable'));
    await tester.pumpAndSettle();
    verify(() => harness.repository.setCpuOverclock(true)).called(1);
  });
}

Future<_PowerHarness> _pumpPage(
  WidgetTester tester, {
  required double width,
  bool dark = false,
  PowerSnapshot? snapshot,
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
  when(() => repository.setCpuOverclock(any())).thenAnswer((_) async {});
  when(() => repository.setGpuOverclock(any())).thenAnswer((_) async {});

  final bloc = PowerBloc(
    repository: repository,
    pollInterval: const Duration(days: 1),
  );
  final loaded = bloc.stream.firstWhere((state) => !state.isLoading);
  bloc.add(const PowerStarted());
  await loaded;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [powerBlocProvider.overrideWith((ref) => bloc)],
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

PowerSnapshot _snapshot() {
  PowerLimitReading reading(String id, int value) => PowerLimitReading(
    spec: PowerRepository.allPowerLimits.firstWhere((spec) => spec.id == id),
    value: value,
  );

  return PowerSnapshot(
    currentMode: const PowerMode('balanced'),
    availableModes: const [
      PowerMode('quiet'),
      PowerMode('balanced'),
      PowerMode('performance'),
      PowerMode('balanced-performance'),
    ],
    powerLimits: [
      reading('cpu_longterm', 55),
      reading('cpu_shortterm', 75),
      reading('gpu_ctgp', 140),
      reading('gpu_temperature', 87),
    ],
    cpuOverclockEnabled: false,
    gpuOverclockEnabled: null,
  );
}

class _PowerHarness {
  const _PowerHarness({required this.repository});

  final _MockPowerRepository repository;
}
