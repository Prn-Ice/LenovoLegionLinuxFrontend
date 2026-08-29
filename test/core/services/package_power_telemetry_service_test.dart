import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/services/package_power_telemetry_service.dart';

void main() {
  group('DBusPackagePowerTelemetryClient.parseSnapshot', () {
    test('returns package watts for an available version 1 snapshot', () {
      final watts = DBusPackagePowerTelemetryClient.parseSnapshot({
        'Available': const DBusBoolean(true),
        'PackagePowerWatts': const DBusDouble(24.75),
        'Version': const DBusString('1'),
      });

      expect(watts, 24.75);
    });

    test('returns null for unavailable telemetry', () {
      final watts = DBusPackagePowerTelemetryClient.parseSnapshot({
        'Available': const DBusBoolean(false),
        'PackagePowerWatts': const DBusDouble(0),
        'Version': const DBusString('1'),
      });

      expect(watts, isNull);
    });

    test('rejects unsupported protocol versions and invalid power', () {
      expect(
        DBusPackagePowerTelemetryClient.parseSnapshot({
          'Available': const DBusBoolean(true),
          'PackagePowerWatts': const DBusDouble(-1),
          'Version': const DBusString('2'),
        }),
        isNull,
      );
    });
  });
}
