import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:integration_test/integration_test.dart';
import 'package:legion_frontend/features/settings/view/settings_page.dart';
import 'package:legion_frontend/features/settings/repository/appearance_store.dart';

import 'scenarios/settings_diagnostics_journey.dart';
import 'support/safe_app.dart';
import 'support/safe_settings.dart';
import 'support/journey.dart';

const _fixturePath = String.fromEnvironment('LLLF_SETTINGS_RESTART_FIXTURE');
const _pidMarker = 'native_settings_restart_process.pid';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;

  testWidgets('restore appearance in a fresh native process', (tester) async {
    expect(_fixturePath, isNotEmpty, reason: 'Pass the settings fixture path');
    final fixture = Directory(_fixturePath);
    final marker = File('${fixture.path}/$_pidMarker');
    expect(await fixture.exists(), isTrue);
    expect(await marker.exists(), isTrue);
    final setupPid = int.parse((await marker.readAsString()).trim());
    expect(
      pid,
      isNot(setupPid),
      reason: 'The phases must use different processes',
    );

    final boxFile = File('${fixture.path}/storage/preferences.hive');
    expect(await boxFile.exists(), isTrue);
    final app = await SafeApp.create(fixtureDirectory: fixture);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await app.dispose();
    });

    final preferences = Hive.box<dynamic>('preferences');
    final persisted = preferences.get(AppearanceStore.key);
    expect(persisted, isA<Map>());
    expect((persisted as Map)['themeMode'], 'dark');
    await app.launch(additionalOverrides: safeSettingsOverrides());
    await openSettings(tester);
    await waitFor(tester, () {
      final settings = tester.element(find.byType(SettingsPage));
      final selector = find.byType(DropdownButtonFormField<ThemeMode>);
      final selected = selector.evaluate().isNotEmpty
          ? tester
                .widget<DropdownButtonFormField<ThemeMode>>(selector.first)
                .initialValue
          : find.byType(SegmentedButton<ThemeMode>).evaluate().isNotEmpty
          ? tester
                .widget<SegmentedButton<ThemeMode>>(
                  find.byType(SegmentedButton<ThemeMode>).first,
                )
                .selected
                .single
          : null;
      return Theme.of(settings).brightness == Brightness.dark &&
          selected == ThemeMode.dark;
    }, description: 'restored dark appearance');
    expect(tester.takeException(), isNull);
  });
}
