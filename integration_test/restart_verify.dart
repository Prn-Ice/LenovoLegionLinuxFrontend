import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:integration_test/integration_test.dart';
import 'package:legion_frontend/features/automation/models/automation_config.dart';
import 'package:legion_frontend/features/automation/repository/automation_repository.dart';
import 'package:legion_frontend/features/automation/view/automation_page.dart';

import 'support/journey.dart';
import 'support/keyboard_journey.dart';
import 'support/safe_app.dart';
import 'support/safe_lighting.dart';

const _fixturePath = String.fromEnvironment('LLLF_GCC_RESTART_FIXTURE');
const _profileName = 'Native restart look';
const _pidMarker = 'native_restart_process.pid';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;

  testWidgets('restore persisted keyboard profile in a fresh native process', (
    tester,
  ) async {
    expect(_fixturePath, isNotEmpty, reason: 'Pass the restart fixture path');
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

    final boxFile = File('${fixture.path}/storage/rgb_lighting.hive');
    final configFile = File('${fixture.path}/automation_rules.json');
    expect(await boxFile.exists(), isTrue);
    expect(await configFile.exists(), isTrue);
    final app = await SafeApp.create(fixtureDirectory: fixture);
    final lighting = SafeLighting(app);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await app.dispose();
    });

    // Read the existing records before launch; this phase never creates or
    // saves the named profile or its automation assignment.
    final box = Hive.box<dynamic>('rgb_lighting');
    expect(box.get('profile:$_profileName'), isA<Map>());
    expect(
      (box.get('profile:$_profileName') as Map)['selectedColor'],
      0xFFFF3311,
    );
    expect((box.get('profile:$_profileName') as Map)['keyColors'], [
      0xFFFF3311,
      0xFFFF3311,
      0xFFFF3311,
    ]);
    expect(box.get('config'), isA<Map>());
    expect(
      (box.get('config') as Map)['selectedColor'],
      0xFF1133FF,
      reason:
          'The persisted current color must differ from the assigned profile',
    );
    expect((box.get('config') as Map)['keyColors'], [
      0xFF1133FF,
      0xFF1133FF,
      0xFF1133FF,
    ]);
    final persisted = await AutomationRepository(
      configFile: configFile,
    ).loadConfig();
    expect(persisted.profiles[KeyboardPowerMode.balanced], _profileName);

    await app.launch(additionalOverrides: lighting.overrides);
    await waitFor(
      tester,
      () => lighting.writes.isNotEmpty,
      description: 'startup RGB write from persisted lighting state',
    );
    await openAutomation(tester);
    expect(find.byType(AutomationPage), findsOneWidget);
    final assignment = find.byWidgetPredicate(
      (widget) =>
          widget is DropdownButtonFormField<String> &&
          widget.decoration.labelText == 'Balanced keyboard profile',
    );
    expect(assignment, findsOneWidget);
    expect(
      tester.widget<DropdownButtonFormField<String>>(assignment).initialValue,
      _profileName,
    );

    await openLighting(tester);
    await waitFor(
      tester,
      () =>
          lighting.writes.lastOrNull?.every((color) => color == 'FF3311') ??
          false,
      description: 'assigned profile overriding the saved manual blue edit',
    );
    expect(lighting.writes.last, ['FF3311', 'FF3311', 'FF3311']);
    final colorField = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.prefixText == '#',
    );
    expect(tester.widget<TextField>(colorField).controller?.text, 'FF3311');
    expect(tester.takeException(), isNull);
  });
}
