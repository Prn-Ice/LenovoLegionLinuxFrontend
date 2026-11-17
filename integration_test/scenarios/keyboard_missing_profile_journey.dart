import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:legion_frontend/features/automation/models/automation_config.dart';
import 'package:legion_frontend/features/automation/repository/automation_repository.dart';
import 'package:yaru/yaru.dart';

import '../support/journey.dart';
import '../support/keyboard_journey.dart';
import '../support/safe_app.dart';
import '../support/safe_lighting.dart';

void main() {
  testWidgets('deleted assigned profile is explained and can be cleared', (
    tester,
  ) async {
    final app = await SafeApp.create();
    final lighting = SafeLighting(app);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await app.dispose();
    });
    await app.launch(additionalOverrides: lighting.overrides);

    await openLighting(tester);
    await paintKeyboard(tester, lighting, 'FF3311');
    await saveKeyboardProfile(tester, 'Recovery look');
    await openAutomation(tester);
    final writesBeforeAssignment = lighting.writes.length;
    await assignKeyboardProfile(
      tester,
      KeyboardPowerMode.balanced,
      'Recovery look',
    );
    await waitFor(
      tester,
      () => lighting.writes.length == writesBeforeAssignment + 1,
      description: 'assigned profile applied before deleting it',
    );

    await openLighting(tester);
    final chip = find.ancestor(
      of: find.text('Recovery look'),
      matching: find.byType(InputChip),
    );
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: chip, matching: find.byIcon(YaruIcons.window_close)),
    );
    await waitFor(
      tester,
      () =>
          Hive.box<dynamic>('rgb_lighting').get('profile:Recovery look') ==
          null,
      description: 'profile deletion persisted through Lighting UI',
    );

    final writesBeforeClear = lighting.writes.length;
    final requestsBeforeClear = lighting.requests.length;
    await openAutomation(tester);
    const guidance =
        'This profile was deleted. Choose another profile or Leave unchanged.';
    await waitFor(
      tester,
      () => find.text(guidance).evaluate().isNotEmpty,
      description: 'missing assignment guidance in Automation',
    );
    expect(find.text('Recovery look (missing)'), findsOneWidget);
    await assignKeyboardProfile(tester, KeyboardPowerMode.balanced, null);
    final repository = AutomationRepository(
      configFile: File('${app.directory.path}/automation_rules.json'),
    );
    expect(
      (await repository.loadConfig()).profiles[KeyboardPowerMode.balanced],
      isNull,
    );
    await waitFor(
      tester,
      () => find.text(guidance).evaluate().isEmpty,
      description: 'cleared assignment removes missing-profile guidance',
    );
    expect(lighting.writes, hasLength(writesBeforeClear));
    expect(lighting.requests, hasLength(requestsBeforeClear));
    expect(tester.takeException(), isNull);
  });
}
