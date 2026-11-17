import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
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
        find.text('Hardware control').evaluate().isNotEmpty,
    description: 'hardware control settings',
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('fresh Settings has no hardware authorization mode chooser', (
    tester,
  ) async {
    final app = await SafeApp.create();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await app.dispose();
    });
    final preferences = Hive.box<dynamic>('preferences');
    expect(preferences.isEmpty, isTrue);
    await app.launch(additionalOverrides: safeSettingsOverrides());
    await _openSettings(tester);
    expect(find.text('Installed service'), findsNothing);
    expect(find.textContaining('In use now:'), findsNothing);
    expect(find.text('Use on next launch'), findsNothing);
    expect(app.authorizations, 0);
    expect(tester.takeException(), isNull);
  });
}
