import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:integration_test/integration_test.dart';
import 'package:legion_frontend/features/automation/models/automation_config.dart';
import 'package:legion_frontend/features/automation/repository/automation_repository.dart';

import 'support/keyboard_journey.dart';
import 'support/journey.dart';
import 'support/safe_app.dart';
import 'support/safe_lighting.dart';

const _fixturePath = String.fromEnvironment('LLLF_GCC_RESTART_FIXTURE');
const _profileName = 'Native restart look';
const _pidMarker = 'native_restart_process.pid';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;

  testWidgets('persist keyboard profile before native process restart', (
    tester,
  ) async {
    expect(_fixturePath, isNotEmpty, reason: 'Pass the restart fixture path');
    final fixture = Directory(_fixturePath);
    expect(await fixture.exists(), isTrue);
    final app = await SafeApp.create(fixtureDirectory: fixture);
    final lighting = SafeLighting(app);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await app.dispose();
    });

    await app.launch(additionalOverrides: lighting.overrides);
    await openLighting(tester);
    await paintKeyboard(tester, lighting, 'FF3311');
    await saveKeyboardProfile(tester, _profileName);

    // Keep this different from the named profile so startup must restore the
    // Balanced assignment rather than merely reuse the last manual edit.
    await paintKeyboard(tester, lighting, '1133FF');
    await openAutomation(tester);
    final writesBeforeAssignment = lighting.writes.length;
    await assignKeyboardProfile(
      tester,
      KeyboardPowerMode.balanced,
      _profileName,
    );
    await waitFor(
      tester,
      () =>
          lighting.writes.length > writesBeforeAssignment &&
          lighting.writes.last.every((color) => color == 'FF3311'),
      description: 'Balanced assignment applying the saved red profile',
    );
    await openLighting(tester);
    await paintKeyboard(tester, lighting, '1133FF');

    final box = Hive.box<dynamic>('rgb_lighting');
    await waitFor(
      tester,
      () =>
          box.get('config') is Map &&
          (box.get('config') as Map)['selectedColor'] == 0xFF1133FF,
      description: 'blue current lighting snapshot persisted to Hive',
    );
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
    expect(
      (box.get('config') as Map)['selectedColor'],
      0xFF1133FF,
      reason: 'The last manual edit must differ from the named profile',
    );
    expect((box.get('config') as Map)['keyColors'], [
      0xFF1133FF,
      0xFF1133FF,
      0xFF1133FF,
    ]);
    final config = await AutomationRepository(
      configFile: File('${fixture.path}/automation_rules.json'),
    ).loadConfig();
    expect(config.profiles[KeyboardPowerMode.balanced], _profileName);
    await File('${fixture.path}/$_pidMarker').writeAsString('$pid\n');

    expect(tester.takeException(), isNull);
  });
}
