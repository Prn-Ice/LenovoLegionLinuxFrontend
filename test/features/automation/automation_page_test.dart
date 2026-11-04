import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaru/yaru.dart';
import 'package:legion_frontend/features/automation/models/automation_config.dart';
import 'package:legion_frontend/features/automation/models/automation_trigger_snapshot.dart';
import 'package:legion_frontend/features/automation/providers/automation_provider.dart';
import 'package:legion_frontend/features/automation/repository/automation_repository.dart';
import 'package:legion_frontend/features/automation/view/automation_page.dart';
import 'package:mocktail/mocktail.dart';

class _AutomationRepo extends Mock implements AutomationRepository {}

class _AutomationConfigFake extends Fake implements AutomationConfig {}

void main() {
  late _AutomationRepo repository;

  setUpAll(() {
    registerFallbackValue(_AutomationConfigFake());
    WidgetController.hitTestWarningShouldBeFatal = true;
  });
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);

  setUp(() {
    repository = _AutomationRepo();
    when(repository.loadConfig).thenAnswer(
      (_) async => AutomationConfig.defaults().copyWith(
        runExternalCommand: true,
        externalCommand: 'notify-send "Automation ran"',
      ),
    );
    when(repository.readTriggerSnapshot).thenAnswer(
      (_) async => const AutomationTriggerSnapshot(
        platformProfile: 'balanced',
        onPowerSupply: true,
      ),
    );
    when(() => repository.saveConfig(any())).thenAnswer((_) async {});
    when(repository.applyFanPresetForCurrentContext).thenAnswer((_) async {});
    when(
      () => repository.applyCustomConservation(
        lowerLimit: any(named: 'lowerLimit'),
        upperLimit: any(named: 'upperLimit'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => repository.setRapidChargingEnabled(any()),
    ).thenAnswer((_) async {});
    when(
      () => repository.runShellCommand(any()),
    ).thenAnswer((_) async => 'done');
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    ThemeMode mode = ThemeMode.light,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [automationRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          themeMode: mode,
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          home: const Scaffold(body: AutomationPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'renders rule vocabulary and preserves actions and run controls',
    (tester) async {
      await pumpPage(tester);
      expect(find.text('Automation runner'), findsOneWidget);
      expect(find.text('Rules'), findsOneWidget);
      expect(find.text('Run command…'), findsOneWidget);
      expect(find.text('Run now'), findsOneWidget);
      expect(find.text('Poll interval: 10 seconds'), findsOneWidget);
      expect(find.text('Battery conservation'), findsOneWidget);
      expect(find.text('Recent run'), findsOneWidget);

      await tester.tap(find.byType(YaruExpandable).first);
      await tester.pumpAndSettle();
      expect(find.text('WHEN'), findsOneWidget);
      expect(find.text('THEN'), findsOneWidget);
      expect(find.text('Trigger on profile change'), findsOneWidget);
      expect(find.text('Trigger on power-source change'), findsOneWidget);
      expect(
        find.text('Apply fan preset on power-context change'),
        findsOneWidget,
      );
      expect(find.text('Apply custom conservation policy'), findsOneWidget);
      expect(find.text('Apply rapid-charging policy'), findsOneWidget);

      await tester.ensureVisible(find.text('Run command on context changes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Run command on context changes'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Enable command action'));
      await tester.pumpAndSettle();
      expect(find.text('Enable command action').hitTestable(), findsOneWidget);
      expect(find.text('Only on context change'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('runner and poll interval persist through production provider', (
    tester,
  ) async {
    await pumpPage(tester);
    await tester.tap(find.text('Run automation rules'));
    await tester.pumpAndSettle();
    verify(
      () => repository.saveConfig(
        any(
          that: isA<AutomationConfig>().having(
            (c) => c.runnerEnabled,
            'runnerEnabled',
            true,
          ),
        ),
      ),
    ).called(1);

    await tester.ensureVisible(find.byType(Slider));
    clearInteractions(repository);
    final slider = tester.getRect(find.byType(Slider));
    await tester.tapAt(Offset(slider.center.dx + 40, slider.center.dy));
    await tester.pumpAndSettle();
    verify(
      () => repository.saveConfig(
        any(
          that: isA<AutomationConfig>().having(
            (c) => c.pollIntervalSeconds,
            'poll interval',
            greaterThan(10),
          ),
        ),
      ),
    ).called(1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('renders the full persisted poll interval range', (tester) async {
    when(repository.loadConfig).thenAnswer(
      (_) async =>
          AutomationConfig.defaults().copyWith(pollIntervalSeconds: 300),
    );
    await pumpPage(tester);
    expect(find.text('Poll interval: 300 seconds'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('run now requires confirmation and reports the completed run', (
    tester,
  ) async {
    await pumpPage(tester);
    await tester.tap(find.text('Run now'));
    await tester.pumpAndSettle();
    expect(find.text('Run automation now'), findsOneWidget);
    verifyNever(() => repository.applyFanPresetForCurrentContext());

    await tester.ensureVisible(find.text('Run now').last);
    await tester.tap(find.text('Run now').last);
    await tester.pumpAndSettle();
    verify(() => repository.applyFanPresetForCurrentContext()).called(1);
    expect(find.text('Recent run'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final mode in ThemeMode.values) {
    testWidgets('fits compact width with enlarged text in $mode', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            automationRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp(
            themeMode: mode,
            theme: ThemeData.light(),
            darkTheme: ThemeData.dark(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: const Scaffold(body: AutomationPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final rule = tester.widget<YaruExpandable>(
        find.byType(YaruExpandable).first,
      );
      await tester.ensureVisible(find.byWidget(rule.header));
      await tester.pumpAndSettle();
      await tester.tap(find.byWidget(rule.header));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Recent run'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Run now'), findsOneWidget);
      expect(find.text('Apply rapid-charging policy'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
