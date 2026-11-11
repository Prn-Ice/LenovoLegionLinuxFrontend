import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:legion_frontend/core/models/control_mode.dart';
import 'package:legion_frontend/features/settings/repository/control_mode_store.dart';
import 'package:legion_frontend/features/settings/view/settings_page.dart';

import '../support/journey.dart';
import '../support/safe_app.dart';
import '../support/safe_settings.dart';

Future<void> _openSettings(WidgetTester tester) async {
  final navigation = find.text('Settings').hitTestable();
  await waitFor(
    tester,
    () => navigation.evaluate().isNotEmpty,
    description: 'Settings navigation',
  );
  await tester.tap(navigation.first);
  await waitFor(
    tester,
    () =>
        find.byType(SettingsPage).evaluate().isNotEmpty &&
        find.text('Temporary helper').evaluate().isNotEmpty,
    description: 'hardware access choices',
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('hardware access choice applies only after reopening the app', (
    tester,
  ) async {
    final fixture = await Directory.systemTemp.createTemp(
      'control-mode-journey-',
    );
    addTearDown(() => fixture.delete(recursive: true));
    var app = await SafeApp.create(fixtureDirectory: fixture);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await app.dispose();
    });
    await app.launch(additionalOverrides: safeSettingsOverrides());
    await _openSettings(tester);
    await tester.ensureVisible(find.text('Temporary helper'));
    await tester.tap(find.text('Temporary helper'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel').hitTestable());
    await tester.pumpAndSettle();
    final preferences = Hive.box<dynamic>('preferences');
    expect(ControlModeStore(preferences).load(), ControlMode.installedService);
    await tester.tap(find.text('Temporary helper'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Use on next launch'));
    await tester.tap(find.text('Use on next launch'));
    await waitFor(
      tester,
      () => ControlModeStore(preferences).load() == ControlMode.temporaryHelper,
      description: 'saved next-launch hardware access',
    );
    expect(
      find.textContaining('Current session: Installed service'),
      findsOneWidget,
    );
    expect(app.authorizations, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await app.dispose();
    app = await SafeApp.create(fixtureDirectory: fixture);
    await app.launch(additionalOverrides: safeSettingsOverrides());
    await _openSettings(tester);
    expect(
      find.textContaining('Current session: Temporary helper'),
      findsOneWidget,
    );
    expect(app.authorizations, 0);
    expect(tester.takeException(), isNull);
  });
}
