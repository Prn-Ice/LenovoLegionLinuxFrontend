import 'dart:io';

import 'package:material_ui/material_ui.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:integration_test/integration_test.dart';

import 'scenarios/settings_diagnostics_journey.dart';
import 'support/safe_app.dart';
import 'support/safe_settings.dart';
import 'support/journey.dart';

const _fixturePath = String.fromEnvironment('LLLF_SETTINGS_RESTART_FIXTURE');
const _pidMarker = 'native_settings_restart_process.pid';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;

  testWidgets('persist native appearance before process restart', (
    tester,
  ) async {
    expect(_fixturePath, isNotEmpty, reason: 'Pass the settings fixture path');
    final fixture = Directory(_fixturePath);
    expect(await fixture.exists(), isTrue);
    final app = await SafeApp.create(fixtureDirectory: fixture);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await app.dispose();
    });

    await app.launch(additionalOverrides: safeSettingsOverrides());
    await openSettings(tester);
    final dark = find.text('Dark').hitTestable();
    await waitFor(
      tester,
      () => dark.evaluate().isNotEmpty,
      description: 'Dark theme control',
    );
    await tester.tap(dark.first);
    await waitFor(
      tester,
      () =>
          (Hive.box<dynamic>('preferences').get('appearance')
              as Map?)?['themeMode'] ==
          'dark',
      description: 'dark appearance persisted',
    );
    await File('${fixture.path}/$_pidMarker').writeAsString('$pid\n');
    expect(tester.takeException(), isNull);
  });
}
