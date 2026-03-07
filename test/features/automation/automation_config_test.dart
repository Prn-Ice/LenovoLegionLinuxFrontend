import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/automation/models/automation_config.dart';

void main() {
  group('AutomationConfig.defaults', () {
    test('runnerEnabled is false', () {
      expect(AutomationConfig.defaults().runnerEnabled, isFalse);
    });

    test('pollIntervalSeconds is 10', () {
      expect(AutomationConfig.defaults().pollIntervalSeconds, equals(10));
    });

    test('conservationLowerLimit is 60, upperLimit is 80', () {
      final d = AutomationConfig.defaults();
      expect(d.conservationLowerLimit, equals(60));
      expect(d.conservationUpperLimit, equals(80));
    });

    test('hasValidConservationRange is true', () {
      expect(AutomationConfig.defaults().hasValidConservationRange, isTrue);
    });
  });

  group('AutomationConfig.fromJson', () {
    test('uses defaults for missing keys', () {
      final c = AutomationConfig.fromJson({});
      expect(c.runnerEnabled, equals(AutomationConfig.defaults().runnerEnabled));
      expect(
        c.pollIntervalSeconds,
        equals(AutomationConfig.defaults().pollIntervalSeconds),
      );
    });

    test('reads runnerEnabled from bool', () {
      final c = AutomationConfig.fromJson({'runnerEnabled': true});
      expect(c.runnerEnabled, isTrue);
    });

    test('ignores non-bool value for runnerEnabled', () {
      final c = AutomationConfig.fromJson({'runnerEnabled': 'yes'});
      expect(c.runnerEnabled, equals(AutomationConfig.defaults().runnerEnabled));
    });

    test('reads pollIntervalSeconds from int', () {
      final c = AutomationConfig.fromJson({'pollIntervalSeconds': 30});
      expect(c.pollIntervalSeconds, equals(30));
    });

    test('reads pollIntervalSeconds from numeric string', () {
      final c = AutomationConfig.fromJson({'pollIntervalSeconds': '60'});
      expect(c.pollIntervalSeconds, equals(60));
    });

    test('clamps pollIntervalSeconds below minimum to 2', () {
      final c = AutomationConfig.fromJson({'pollIntervalSeconds': 1});
      expect(c.pollIntervalSeconds, equals(2));
    });

    test('clamps pollIntervalSeconds above maximum to 300', () {
      final c = AutomationConfig.fromJson({'pollIntervalSeconds': 9999});
      expect(c.pollIntervalSeconds, equals(300));
    });

    test('clamps conservationLowerLimit to [0, 100]', () {
      final low = AutomationConfig.fromJson({'conservationLowerLimit': -5});
      expect(low.conservationLowerLimit, equals(0));
      final high = AutomationConfig.fromJson({'conservationLowerLimit': 200});
      expect(high.conservationLowerLimit, equals(100));
    });

    test('reads all boolean fields correctly', () {
      final c = AutomationConfig.fromJson({
        'applyFanPresetOnContextChange': false,
        'triggerOnProfileChange': false,
        'triggerOnPowerSourceChange': true,
        'applyCustomConservation': true,
        'applyRapidChargingPolicy': true,
        'rapidChargingOnAc': false,
        'rapidChargingOnBattery': true,
      });
      expect(c.applyFanPresetOnContextChange, isFalse);
      expect(c.triggerOnProfileChange, isFalse);
      expect(c.triggerOnPowerSourceChange, isTrue);
      expect(c.applyCustomConservation, isTrue);
      expect(c.applyRapidChargingPolicy, isTrue);
      expect(c.rapidChargingOnAc, isFalse);
      expect(c.rapidChargingOnBattery, isTrue);
    });
  });

  group('AutomationConfig.copyWith', () {
    test('copyWith(pollIntervalSeconds: 1) clamps to 2', () {
      final c = AutomationConfig.defaults().copyWith(pollIntervalSeconds: 1);
      expect(c.pollIntervalSeconds, equals(2));
    });

    test('copyWith preserves unchanged fields', () {
      final c = AutomationConfig.defaults().copyWith(runnerEnabled: true);
      expect(c.pollIntervalSeconds, equals(10));
    });
  });

  group('AutomationConfig.hasValidConservationRange', () {
    test('true when lower <= upper', () {
      final c = AutomationConfig.defaults().copyWith(
        conservationLowerLimit: 60,
        conservationUpperLimit: 80,
      );
      expect(c.hasValidConservationRange, isTrue);
    });

    test('true when lower == upper', () {
      final c = AutomationConfig.defaults().copyWith(
        conservationLowerLimit: 70,
        conservationUpperLimit: 70,
      );
      expect(c.hasValidConservationRange, isTrue);
    });

    test('false when lower > upper', () {
      final c = AutomationConfig.defaults().copyWith(
        conservationLowerLimit: 90,
        conservationUpperLimit: 60,
      );
      expect(c.hasValidConservationRange, isFalse);
    });
  });
}
