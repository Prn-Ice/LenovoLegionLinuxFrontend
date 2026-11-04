import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:legion_frontend/features/automation/models/automation_config.dart';
import 'package:legion_frontend/features/automation/view/automation_page.dart';
import 'package:legion_frontend/features/dashboard/view/dashboard_page.dart';
import 'package:legion_frontend/features/lighting/view/lighting_page.dart';

import 'journey.dart';
import 'safe_lighting.dart';

Future<void> openLighting(WidgetTester tester) async {
  final navigation = find.text('Lighting').hitTestable();
  await waitFor(
    tester,
    () => navigation.evaluate().isNotEmpty,
    description: 'Lighting navigation control',
  );
  await tester.tap(navigation.first);
  final nameField = find.byWidgetPredicate(
    (widget) =>
        widget is TextField && widget.decoration?.hintText == 'Profile name',
  );
  await waitFor(
    tester,
    () =>
        find.byType(LightingPage).evaluate().isNotEmpty &&
        find.text('Journey keyboard').evaluate().isNotEmpty &&
        nameField.evaluate().length == 1,
    description: 'Lighting page, discovered keyboard, and unique profile input',
  );
  await tester.pumpAndSettle();
  expect(nameField, findsOneWidget);
}

Future<void> paintKeyboard(
  WidgetTester tester,
  SafeLighting lighting,
  String hex,
) async {
  final colorField = find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.prefixText == '#',
  );
  await tester.ensureVisible(colorField);
  final writesBefore = lighting.writes.length;
  await tester.enterText(colorField, hex);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await waitFor(
    tester,
    () => lighting.writes.length == writesBefore + 1,
    description: 'one RGB write for color $hex',
  );
  expect(lighting.writes, hasLength(writesBefore + 1));
  expect(lighting.writes.last, [hex, hex, hex]);
}

Future<void> saveKeyboardProfile(WidgetTester tester, String name) async {
  final nameField = find.byWidgetPredicate(
    (widget) =>
        widget is TextField && widget.decoration?.hintText == 'Profile name',
  );
  await tester.ensureVisible(nameField);
  await tester.enterText(nameField, name);
  await tester.tap(find.text('Save').hitTestable().last);
  await waitFor(tester, () {
    final box = Hive.box<dynamic>('rgb_lighting');
    final names = box.get('profileNames');
    return box.get('profile:$name') is Map &&
        names is List &&
        names.contains(name);
  }, description: 'saved keyboard profile $name in Hive');
}

Future<void> openAutomation(WidgetTester tester) async {
  final navigation = find.text('Automation').hitTestable();
  await waitFor(
    tester,
    () => navigation.evaluate().isNotEmpty,
    description: 'Automation navigation control',
  );
  await tester.tap(navigation.first);
  final assignments = find.byType(DropdownButtonFormField<String>);
  await waitFor(
    tester,
    () =>
        find.byType(AutomationPage).evaluate().isNotEmpty &&
        assignments.evaluate().length == KeyboardPowerMode.values.length,
    description: 'loaded Automation page and profile assignment selectors',
  );
  await tester.pumpAndSettle();
}

Future<void> assignKeyboardProfile(
  WidgetTester tester,
  KeyboardPowerMode mode,
  String? name,
) async {
  final assignment = find.byWidgetPredicate(
    (widget) =>
        widget is DropdownButtonFormField<String> &&
        widget.decoration.labelText == '${mode.label} keyboard profile',
  );
  await waitFor(
    tester,
    () => assignment.evaluate().length == 1,
    description: '${mode.label} keyboard profile selector',
  );
  await tester.ensureVisible(assignment);
  await tester.pumpAndSettle();
  await tester.tap(assignment);
  await tester.pumpAndSettle();
  await tester.tap(
    name == null
        ? find.text('Leave unchanged').hitTestable().last
        : find.text(name).hitTestable().last,
  );
  await waitFor(tester, () {
    final dropdown = tester.widget<DropdownButtonFormField<String>>(assignment);
    return dropdown.initialValue == name && dropdown.onChanged != null;
  }, description: 'saved ${mode.label} assignment to ${name ?? 'unchanged'}');
}

Future<void> openDashboard(WidgetTester tester) async {
  final navigation = find.text('Dashboard').hitTestable();
  await waitFor(
    tester,
    () => navigation.evaluate().isNotEmpty,
    description: 'Dashboard navigation control',
  );
  await tester.tap(navigation.first);
  await waitFor(
    tester,
    () => find.byType(DashboardPage).evaluate().isNotEmpty,
    description: 'Dashboard page',
  );
  await tester.pumpAndSettle();
}
