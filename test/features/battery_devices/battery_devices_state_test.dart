// test/features/battery_devices/battery_devices_state_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/battery_devices/bloc/battery_devices_state.dart';

void main() {
  group('BatteryDevicesState fnLock', () {
    test('initial state has fnLockEnabled as null', () {
      final state = BatteryDevicesState.initial();
      expect(state.fnLockEnabled, isNull);
    });

    test('copyWith fnLockEnabled: true sets it', () {
      final state = BatteryDevicesState.initial().copyWith(fnLockEnabled: true);
      expect(state.fnLockEnabled, isTrue);
    });

    test('copyWith fnLockEnabled: null preserves null', () {
      final state = BatteryDevicesState.initial();
      // copyWith with no fnLockEnabled arg must not change it
      final updated = state.copyWith(isLoading: false);
      expect(updated.fnLockEnabled, isNull);
    });

    test('hasLoaded is true when only fnLockEnabled is set', () {
      final state = BatteryDevicesState.initial().copyWith(
        fnLockEnabled: false,
      );
      expect(state.hasLoaded, isTrue);
    });

    test('props distinguishes fnLockEnabled true vs false', () {
      final s1 = BatteryDevicesState.initial().copyWith(fnLockEnabled: true);
      final s2 = BatteryDevicesState.initial().copyWith(fnLockEnabled: false);
      expect(s1, isNot(equals(s2)));
    });
  });
}
