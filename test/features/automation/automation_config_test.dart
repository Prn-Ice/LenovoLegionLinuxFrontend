import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/automation/models/automation_config.dart';
import 'package:legion_frontend/features/automation/repository/automation_repository.dart';

void main() {
  test(
    'legacy enabled rules migrate to leave unchanged and are removed on save',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'keyboard-migration-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/automation_rules.json');
      await file.writeAsString(
        jsonEncode({
          'runnerEnabled': true,
          'applyFanPresetOnContextChange': true,
          'applyCustomConservation': true,
          'applyRapidChargingPolicy': true,
          'runExternalCommand': true,
          'externalCommand': 'touch unwanted',
        }),
      );
      final repository = AutomationRepository(configFile: file);
      final config = await repository.loadConfig();
      expect(config.profiles, isEmpty);
      final assigned = config.assign(KeyboardPowerMode.quiet, 'Night');
      await repository.saveConfig(assigned);
      expect(await repository.loadConfig(), assigned);
      expect(jsonDecode(await file.readAsString()), {
        'version': 2,
        'keyboardProfiles': {'quiet': 'Night'},
      });
      await repository.saveConfig(
        assigned.assign(KeyboardPowerMode.quiet, null),
      );
      expect((await repository.loadConfig()).profiles, isEmpty);
    },
  );

  test('malformed mappings are ignored without inventing mode choices', () {
    final config = AutomationConfig.fromJson({
      'keyboardProfiles': {
        'quiet': '',
        'balanced': 42,
        'custom': 'Studio',
        'unknown': 'Other',
      },
    });
    expect(config.profiles, {KeyboardPowerMode.custom: 'Studio'});
    expect(
      KeyboardPowerMode.fromPlatformProfile('low-power'),
      KeyboardPowerMode.quiet,
    );
    expect(
      KeyboardPowerMode.fromPlatformProfile('power-saver'),
      KeyboardPowerMode.quiet,
    );
    expect(
      KeyboardPowerMode.fromPlatformProfile('balanced-performance'),
      KeyboardPowerMode.custom,
    );
    expect(KeyboardPowerMode.fromPlatformProfile('unknown'), isNull);
  });
}
