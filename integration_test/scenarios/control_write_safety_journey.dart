import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:legion_frontend/core/widgets/app_shell_components.dart';
import 'package:legion_frontend/features/battery/bloc/battery_bloc.dart';
import 'package:legion_frontend/features/battery/bloc/battery_event.dart';
import 'package:legion_frontend/features/battery/providers/battery_provider.dart';
import 'package:legion_frontend/features/battery/view/battery_page.dart';
import 'package:legion_frontend/features/power/view/power_page.dart';
import 'package:yaru/yaru.dart';

import '../support/journey.dart';
import '../support/safe_app.dart';

void main() {
  for (final result in [
    FixtureRapidChargingResult.unchanged,
    FixtureRapidChargingResult.readbackUnavailable,
  ]) {
    final description = result == FixtureRapidChargingResult.unchanged
        ? 'unchanged'
        : 'unavailable';
    testWidgets('charging $description readback reports failure and recovers', (
      tester,
    ) async {
      final app = await _launch(tester);
      app.rapidChargingResult = result;
      await _enableRapidCharging(tester);
      await waitFor(
        tester,
        () => find.byType(AppErrorDialog).evaluate().isNotEmpty,
        description: '$description charging readback failure',
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Rapid charging could not be confirmed.'),
        findsOneWidget,
      );
      final state = _container(tester, PowerPage).read(batteryBlocProvider);
      expect(state.isApplying, isFalse);
      expect(state.noticeMessage, isNull);
      expect(app.rapidChargingRequests, [true]);
      if (result == FixtureRapidChargingResult.unchanged) {
        expect(state.rapidChargingEnabled, isFalse);
        expect(_switch(tester).value, isFalse);
        expect(app.rapidChargingWrites, isEmpty);
        expect(await app.rapidChargingFile.readAsString(), '0\n');
      } else {
        expect(state.rapidChargingEnabled, isNull);
        expect(state.rapidChargingSupported, isFalse);
        expect(find.text('Rapid charging'), findsNothing);
        expect(app.rapidChargingWrites, [true]);
        expect(await app.rapidChargingFile.exists(), isFalse);
      }
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      // Restore readings only. The next setting change must still use the UI.
      await app.rapidChargingFile.writeAsString('0\n');
      app.rapidChargingResult = FixtureRapidChargingResult.applied;
      await tester.tap(find.byTooltip('Refresh'));
      await waitFor(tester, () {
        final state = _container(tester, PowerPage).read(batteryBlocProvider);
        return !state.isLoading &&
            state.rapidChargingSupported &&
            state.rapidChargingEnabled == false;
      }, description: 'restored charging readings after explicit Refresh');
      await _enableRapidCharging(tester);
      await waitFor(
        tester,
        () => _switch(tester).value,
        description: 'successful charging retry readback',
      );
      expect(app.rapidChargingRequests, [true, true]);
      expect(await app.rapidChargingFile.readAsString(), '1\n');
      expect(find.byType(AppErrorDialog), findsNothing);
      expect(app.requests, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('pending charging write completes after navigation to Battery', (
    tester,
  ) async {
    final app = await _launch(tester);
    final completion = app.writeCompletion = Completer<void>();
    final container = _container(tester, PowerPage);
    final battery = container.read(batteryBlocProvider.bloc);
    await _enableRapidCharging(tester);
    await waitFor(
      tester,
      () => app.rapidChargingRequests.isNotEmpty,
      description: 'pending charging request',
    );
    await tester.pumpAndSettle();
    expect(_switch(tester).value, isFalse);
    expect(_switch(tester).onChanged, isNull);
    await _navigate(tester, 'Battery', BatteryPage);
    expect(_container(tester, BatteryPage), same(container));
    expect(container.read(batteryBlocProvider.bloc), same(battery));
    expect(container.read(batteryBlocProvider).isApplying, isTrue);
    expect(container.read(batteryBlocProvider).rapidChargingEnabled, isFalse);
    expect(app.rapidChargingWrites, isEmpty);
    expect(await app.rapidChargingFile.readAsString(), '0\n');
    completion.complete();
    await waitFor(
      tester,
      () =>
          !container.read(batteryBlocProvider).isApplying &&
          container.read(batteryBlocProvider).rapidChargingEnabled == true,
      description: 'charging completion retained across page navigation',
    );
    await _navigate(tester, 'Power', PowerPage);
    await tester.ensureVisible(switchInCard('Rapid charging'));
    await tester.pumpAndSettle();
    expect(_switch(tester).value, isTrue);
    expect(_switch(tester).onChanged, isNotNull);
    expect(app.rapidChargingRequests, [true]);
    expect(app.rapidChargingWrites, [true]);
    expect(await app.rapidChargingFile.readAsString(), '1\n');
    expect(app.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

Future<SafeApp> _launch(WidgetTester tester) async {
  final app = await SafeApp.create(includeRapidChargingFixture: true);
  addTearDown(() async {
    final completion = app.writeCompletion;
    if (completion != null && !completion.isCompleted) completion.complete();
    await tester.pumpWidget(const SizedBox.shrink());
    await app.dispose();
  });
  await app.launch(
    additionalOverrides: [
      batteryBlocProvider.overrideWith(
        (ref) => BatteryBloc(
          repository: ref.watch(batteryRepositoryProvider),
          pollInterval: const Duration(days: 1),
        )..add(const BatteryStarted()),
      ),
    ],
  );
  await _navigate(tester, 'Power', PowerPage);
  await waitFor(
    tester,
    () => switchInCard('Rapid charging').evaluate().length == 1,
    description: 'supported rapid-charging control',
  );
  return app;
}

Future<void> _enableRapidCharging(WidgetTester tester) async {
  final control = switchInCard('Rapid charging');
  await tester.ensureVisible(control);
  await tester.pumpAndSettle();
  expect(_switch(tester).value, isFalse);
  await tester.tap(control);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Enable'));
  await tester.pump();
}

Future<void> _navigate(WidgetTester tester, String label, Type page) async {
  await waitFor(
    tester,
    () => find.text(label).hitTestable().evaluate().isNotEmpty,
    description: '$label navigation',
  );
  await tester.tap(find.text(label).hitTestable().first);
  await tester.pumpAndSettle();
  await waitFor(
    tester,
    () => find.byType(page).evaluate().length == 1,
    description: '$label page',
  );
}

ProviderContainer _container(WidgetTester tester, Type page) =>
    ProviderScope.containerOf(tester.element(find.byType(page)));

YaruSwitch _switch(WidgetTester tester) =>
    tester.widget<YaruSwitch>(switchInCard('Rapid charging'));
