import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:legion_frontend/core/models/app_failure.dart';
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
  testWidgets('rapid charging cancels, applies, and refreshes across pages', (
    tester,
  ) async {
    // On battery, this is a saved preference, not a claim that charging started.
    final app = await _launch(tester);
    await _openConfirmation(tester, enabled: true);
    expect(app.authorizations, 0);
    expect(app.rapidChargingRequests, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(_switch(tester).value, isFalse);
    expect(app.authorizations, 0);
    expect(app.rapidChargingRequests, isEmpty);
    expect(app.rapidChargingWrites, isEmpty);
    expect(await app.rapidChargingFile.readAsString(), '0\n');

    await _apply(tester, enabled: true);
    await _waitForReadback(tester, enabled: true);
    expect(app.rapidChargingRequests, [true]);
    expect(app.rapidChargingWrites, [true]);
    expect(app.authorizations, 1);
    expect(await app.rapidChargingFile.readAsString(), '1\n');

    await _navigate(tester, 'Battery', BatteryPage);
    final container = _container(tester, BatteryPage);
    expect(container.read(batteryBlocProvider).rapidChargingEnabled, isTrue);
    // Simulate a firmware change. With polling paused, Refresh must load it.
    await app.rapidChargingFile.writeAsString('0\n');
    expect(container.read(batteryBlocProvider).rapidChargingEnabled, isTrue);
    await tester.tap(find.byTooltip('Refresh'));
    await waitFor(
      tester,
      () =>
          !container.read(batteryBlocProvider).isLoading &&
          container.read(batteryBlocProvider).rapidChargingEnabled == false,
      description:
          'Battery Refresh reads the changed rapid-charging preference',
    );
    await _navigate(tester, 'Power', PowerPage);
    await tester.ensureVisible(switchInCard('Rapid charging'));
    await tester.pumpAndSettle();
    expect(_switch(tester).value, isFalse);
    expect(app.rapidChargingRequests, [true]);
    expect(app.rapidChargingWrites, [true]);
    await _expectUnrelatedControlsUntouched(app);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'rapid charging preserves confirmed state on failure and pending retry',
    (tester) async {
      final app = await _launch(tester);
      await _apply(tester, enabled: true);
      await _waitForReadback(tester, enabled: true);
      app.nextFailure = ControlFailure.commandFailed;
      await _apply(tester, enabled: false);
      await waitFor(
        tester,
        () => find.byType(AppErrorDialog).evaluate().isNotEmpty,
        description: 'failed rapid-charging write dialog',
      );
      await tester.pumpAndSettle();
      final dialog = tester.widget<AppErrorDialog>(find.byType(AppErrorDialog));
      expect(
        AppFailure.from(dialog.message).kind,
        AppFailureKind.commandFailed,
      );
      expect(
        find.textContaining('Failed to set rapid charging to off'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Test backend rejected the write'),
        findsOneWidget,
      );
      expect(_switch(tester).value, isTrue);
      final failedState = _container(
        tester,
        PowerPage,
      ).read(batteryBlocProvider);
      expect(failedState.rapidChargingEnabled, isTrue);
      expect(failedState.isApplying, isFalse);
      expect(failedState.noticeMessage, isNull);
      expect(await app.rapidChargingFile.readAsString(), '1\n');
      expect(app.rapidChargingRequests, [true, false]);
      expect(app.rapidChargingWrites, [true]);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      final completion = app.writeCompletion = Completer<void>();
      await _apply(tester, enabled: false);
      await waitFor(
        tester,
        () => app.rapidChargingRequests.length == 3,
        description: 'pending rapid-charging retry reaches the backend',
      );
      await tester.pumpAndSettle();
      expect(_switch(tester).value, isTrue);
      expect(_switch(tester).onChanged, isNull);
      expect(app.rapidChargingWrites, [true]);
      expect(await app.rapidChargingFile.readAsString(), '1\n');
      await tester.tap(switchInCard('Rapid charging'));
      await tester.pump();
      expect(app.rapidChargingRequests, [true, false, false]);
      expect(find.text('Disable rapid charging'), findsNothing);

      completion.complete();
      await _waitForReadback(tester, enabled: false);
      expect(_switch(tester).onChanged, isNotNull);
      expect(app.rapidChargingRequests, [true, false, false]);
      expect(app.rapidChargingWrites, [true, false]);
      expect(await app.rapidChargingFile.readAsString(), '0\n');
      expect(find.byType(AppErrorDialog), findsNothing);
      await _expectUnrelatedControlsUntouched(app);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unsupported rapid charging exposes no Power control or write', (
    tester,
  ) async {
    final app = await _launch(tester, supported: false);
    expect(find.text('Rapid charging'), findsNothing);
    expect(app.authorizations, 0);
    expect(app.rapidChargingRequests, isEmpty);
    expect(app.rapidChargingWrites, isEmpty);
    expect(await app.rapidChargingFile.exists(), isFalse);
    expect(
      _container(
        tester,
        PowerPage,
      ).read(batteryBlocProvider).rapidChargingSupported,
      isFalse,
    );
    await _expectUnrelatedControlsUntouched(app);
    expect(tester.takeException(), isNull);
  });
}

Future<SafeApp> _launch(WidgetTester tester, {bool supported = true}) async {
  final app = await SafeApp.create(
    acOnline: false,
    includeRapidChargingFixture: supported,
  );
  addTearDown(() async {
    final completion = app.writeCompletion;
    if (completion != null && !completion.isCompleted) completion.complete();
    await tester.pumpWidget(const SizedBox.shrink());
    await app.dispose();
  });
  await app.launch(
    additionalOverrides: [
      // Require explicit refresh and write readback, not a later periodic read.
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
    () => _container(tester, PowerPage).read(batteryBlocProvider).hasLoaded,
    description: 'battery controls loaded on Power',
  );
  await tester.pumpAndSettle();
  if (supported) {
    await tester.ensureVisible(switchInCard('Rapid charging'));
    await tester.pumpAndSettle();
    expect(_switch(tester).value, isFalse);
  }
  return app;
}

Future<void> _navigate(WidgetTester tester, String label, Type page) async {
  final navigation = find.text(label).hitTestable();
  await waitFor(
    tester,
    () => navigation.evaluate().isNotEmpty,
    description: '$label navigation',
  );
  await tester.tap(navigation.first);
  await waitFor(
    tester,
    () => find.byType(page).evaluate().isNotEmpty,
    description: '$label page',
  );
  await tester.pumpAndSettle();
}

Future<void> _openConfirmation(
  WidgetTester tester, {
  required bool enabled,
}) async {
  final control = switchInCard('Rapid charging');
  await tester.ensureVisible(control);
  await tester.pumpAndSettle();
  expect(_switch(tester).value, !enabled);
  await tester.tap(control);
  await tester.pumpAndSettle();
  expect(
    find.text('${enabled ? 'Enable' : 'Disable'} rapid charging'),
    findsOneWidget,
  );
}

Future<void> _apply(WidgetTester tester, {required bool enabled}) async {
  await _openConfirmation(tester, enabled: enabled);
  await tester.tap(find.text(enabled ? 'Enable' : 'Disable'));
  await tester.pump();
}

Future<void> _waitForReadback(WidgetTester tester, {required bool enabled}) =>
    waitFor(
      tester,
      () =>
          !_container(tester, PowerPage).read(batteryBlocProvider).isApplying &&
          _switch(tester).value == enabled,
      description: 'confirmed rapid-charging readback on Power',
    );

YaruSwitch _switch(WidgetTester tester) =>
    tester.widget<YaruSwitch>(switchInCard('Rapid charging'));

ProviderContainer _container(WidgetTester tester, Type page) =>
    ProviderScope.containerOf(tester.element(find.byType(page)));

Future<void> _expectUnrelatedControlsUntouched(SafeApp app) async {
  expect(await app.conservationFile.readAsString(), '0\n');
  expect(app.requests, isEmpty);
  expect(app.writes, isEmpty);
  expect(app.platformProfileRequests, isEmpty);
  expect(app.powerLimitRequests, isEmpty);
  expect(app.fanPresetRequests, isEmpty);
}
