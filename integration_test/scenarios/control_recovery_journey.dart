import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/models/app_failure.dart';
import 'package:legion_frontend/core/widgets/app_shell_components.dart';
import 'package:yaru/yaru.dart';

import '../support/journey.dart';
import '../support/safe_app.dart';

void main() {
  for (final failure in ControlFailure.values) {
    testWidgets('Battery health recovers from ${failure.name}', (tester) async {
      final app = await launchApp(tester);
      app.nextFailure = failure;
      final healthSwitch = switchInCard('Battery health');
      await applyBatteryHealth(tester, healthSwitch);
      await waitFor(
        tester,
        () => find.byType(AppErrorDialog).evaluate().isNotEmpty,
        description: '${failure.name} error dialog',
      );
      await tester.pumpAndSettle();

      final dialog = tester.widget<AppErrorDialog>(find.byType(AppErrorDialog));
      expect(AppFailure.from(dialog.message).kind, switch (failure) {
        ControlFailure.permissionDenied => AppFailureKind.permissionDenied,
        ControlFailure.unavailable => AppFailureKind.unavailable,
        ControlFailure.commandFailed => AppFailureKind.commandFailed,
      });
      expect(find.text('Action could not be completed'), findsOneWidget);
      expect(
        find.textContaining('No confirmation was received'),
        findsOneWidget,
      );
      expect(tester.widget<YaruSwitch>(healthSwitch).value, isFalse);
      expect(app.writes, isEmpty);
      expect(await app.conservationFile.readAsString(), '0\n');
      expect(app.authorizations, 1);
      expect(
        app.requests,
        failure == ControlFailure.commandFailed ? [true] : isEmpty,
      );

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await applyBatteryHealth(tester, healthSwitch);
      await waitFor(
        tester,
        () => tester.widget<YaruSwitch>(healthSwitch).value,
        description: 'successful retry readback',
      );
      expect(find.byType(AppErrorDialog), findsNothing);
      expect(app.writes, [true]);
      expect(await app.conservationFile.readAsString(), '1\n');
      expect(app.authorizations, 2);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Battery health remains unchanged while a write is pending', (
    tester,
  ) async {
    final app = await launchApp(tester);
    final completion = app.writeCompletion = Completer<void>();
    final healthSwitch = switchInCard('Battery health');
    await applyBatteryHealth(tester, healthSwitch);
    await waitFor(
      tester,
      () => app.requests.isNotEmpty,
      description: 'pending backend request',
    );
    expect(tester.widget<YaruSwitch>(healthSwitch).value, isFalse);
    expect(tester.widget<YaruSwitch>(healthSwitch).onChanged, isNull);
    expect(app.writes, isEmpty);
    expect(await app.conservationFile.readAsString(), '0\n');

    completion.complete();
    await waitFor(
      tester,
      () => tester.widget<YaruSwitch>(healthSwitch).value,
      description: 'completed write readback',
    );
    expect(tester.widget<YaruSwitch>(healthSwitch).onChanged, isNotNull);
    expect(app.requests, [true]);
    expect(app.writes, [true]);
    expect(tester.takeException(), isNull);
  });
}

Future<SafeApp> launchApp(WidgetTester tester) async {
  final app = await SafeApp.create();
  addTearDown(() async {
    // Release controlled I/O even when an assertion fails while it is pending.
    final completion = app.writeCompletion;
    if (completion != null && !completion.isCompleted) completion.complete();
    await tester.pumpWidget(const SizedBox.shrink());
    await app.dispose();
  });
  await app.launch();
  final healthSwitch = switchInCard('Battery health');
  await waitFor(
    tester,
    () => healthSwitch.evaluate().isNotEmpty,
    description: 'Dashboard Battery health control',
  );
  await tester.ensureVisible(healthSwitch);
  await tester.pumpAndSettle();
  return app;
}

Future<void> applyBatteryHealth(WidgetTester tester, Finder control) async {
  await tester.tap(control);
  await tester.pumpAndSettle();
  expect(find.text('Set battery conservation'), findsOneWidget);
  await tester.tap(find.text('Apply'));
  await tester.pump();
}
