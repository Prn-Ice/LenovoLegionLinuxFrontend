import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:legion_frontend/features/automation/models/automation_config.dart';
import 'package:legion_frontend/features/automation/repository/automation_repository.dart';
import 'package:legion_frontend/features/automation/view/automation_page.dart';
import 'package:legion_frontend/features/lighting/view/lighting_page.dart';

import '../support/journey.dart';
import '../support/safe_app.dart';
import '../support/safe_lighting.dart';

void main() {
  testWidgets('save a Lighting profile and assign it to Balanced', (
    tester,
  ) async {
    final app = await SafeApp.create();
    final lighting = SafeLighting(app);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await app.dispose();
    });
    await app.launch(additionalOverrides: lighting.overrides);

    final lightingNavigation = find.text('Lighting').hitTestable();
    await waitFor(
      tester,
      () => lightingNavigation.evaluate().isNotEmpty,
      description: 'Lighting navigation control after app launch',
    );
    await tester.tap(lightingNavigation.first);
    final nameField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.hintText == 'Profile name',
    );
    await waitFor(
      tester,
      () =>
          find.byType(LightingPage).evaluate().isNotEmpty &&
          nameField.evaluate().isNotEmpty &&
          find.text('Journey keyboard').evaluate().isNotEmpty,
      description: 'Lighting profile controls and keyboard discovery',
    );
    await tester.pumpAndSettle();
    expect(nameField, findsOneWidget);
    await tester.ensureVisible(nameField);

    final colorField = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.prefixText == '#',
    );
    await tester.ensureVisible(colorField);
    await tester.enterText(colorField, 'FF3311');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await waitFor(
      tester,
      () => lighting.writes.length == 1,
      description: 'distinct RGB color applied through the Lighting UI',
    );
    expect(lighting.writes.single, ['FF3311', 'FF3311', 'FF3311']);

    await tester.ensureVisible(nameField);
    await tester.enterText(nameField, 'Journey look');
    await tester.tap(find.text('Save').hitTestable().last);
    await waitFor(tester, () {
      final box = Hive.box<dynamic>('rgb_lighting');
      final names = box.get('profileNames');
      return box.get('profile:Journey look') is Map &&
          names is List &&
          names.contains('Journey look');
    }, description: 'named profile persisted in the RGB Hive store');
    expect(
      Hive.box<dynamic>('rgb_lighting').get('profile:Journey look'),
      isA<Map>(),
    );

    // Change the current lighting so assigning the saved profile must restore
    // its stored colors rather than simply resend the current configuration.
    await tester.ensureVisible(colorField);
    await tester.enterText(colorField, '1133FF');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await waitFor(
      tester,
      () => lighting.writes.length == 2,
      description: 'manual lighting edit after saving the profile',
    );
    expect(lighting.writes.last, ['1133FF', '1133FF', '1133FF']);
    final writesBeforeAssignment = lighting.writes.length;

    await tester.tap(find.text('Automation').hitTestable().first);
    await waitFor(
      tester,
      () =>
          find.byType(AutomationPage).evaluate().isNotEmpty &&
          find.text('Current mode: Balanced').evaluate().isNotEmpty,
      description: 'Automation showing the current Balanced mode',
    );
    final balancedAssignment = find
        .byType(DropdownButtonFormField<String>)
        .at(KeyboardPowerMode.values.indexOf(KeyboardPowerMode.balanced));
    await tester.ensureVisible(balancedAssignment);
    await tester.pumpAndSettle();
    await tester.tap(balancedAssignment);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Journey look').last);

    await waitFor(
      tester,
      () => lighting.writes.length == writesBeforeAssignment + 1,
      description: 'assigned profile applied through the RGB Bloc',
    );
    expect(lighting.writes, hasLength(writesBeforeAssignment + 1));
    expect(lighting.writes.last, ['FF3311', 'FF3311', 'FF3311']);

    final repository = AutomationRepository(
      configFile: File('${app.directory.path}/automation_rules.json'),
    );
    final persisted = await repository.loadConfig();
    expect(persisted.profiles[KeyboardPowerMode.balanced], 'Journey look');

    await tester.pumpAndSettle();
    await tester.tap(balancedAssignment);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave unchanged').hitTestable().last);
    await waitFor(tester, () {
      final dropdown = tester.widget<DropdownButtonFormField<String>>(
        balancedAssignment,
      );
      return dropdown.initialValue == null && dropdown.onChanged != null;
    }, description: 'cleared and saved Balanced assignment');
    expect(
      (await repository.loadConfig()).profiles[KeyboardPowerMode.balanced],
      isNull,
    );
    expect(lighting.writes, hasLength(writesBeforeAssignment + 1));
    expect(tester.takeException(), isNull);
  });
}
