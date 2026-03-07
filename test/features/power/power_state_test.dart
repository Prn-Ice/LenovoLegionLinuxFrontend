import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/power/bloc/power_state.dart';
import 'package:legion_frontend/features/power/models/power_mode.dart';

void main() {
  group('PowerMode', () {
    test('fromRaw strips brackets', () {
      final mode = PowerMode.fromRaw('[balanced]');
      expect(mode.value, equals('balanced'));
    });

    test('fromRaw handles value without brackets', () {
      final mode = PowerMode.fromRaw('quiet');
      expect(mode.value, equals('quiet'));
    });

    test('label returns human-readable string for known values', () {
      expect(const PowerMode('quiet').label, equals('Quiet'));
      expect(const PowerMode('balanced').label, equals('Balanced'));
      expect(const PowerMode('performance').label, equals('Performance'));
      expect(const PowerMode('balanced-performance').label, equals('Custom'));
    });

    test('label returns raw value for unknown modes', () {
      expect(const PowerMode('ultra').label, equals('ultra'));
    });

    test('equality based on value', () {
      expect(const PowerMode('quiet'), equals(const PowerMode('quiet')));
      expect(
        const PowerMode('quiet'),
        isNot(equals(const PowerMode('balanced'))),
      );
    });
  });

  group('PowerState.initial', () {
    test('currentMode is null', () {
      expect(PowerState.initial().currentMode, isNull);
    });

    test('availableModes and powerLimits are empty', () {
      expect(PowerState.initial().availableModes, isEmpty);
      expect(PowerState.initial().powerLimits, isEmpty);
    });

    test('hasLoaded is false', () {
      expect(PowerState.initial().hasLoaded, isFalse);
    });
  });

  group('PowerState.hasLoaded', () {
    test('true when currentMode is set', () {
      final s = PowerState.initial().copyWith(
        currentMode: const PowerMode('balanced'),
      );
      expect(s.hasLoaded, isTrue);
    });

    test('true when availableModes is non-empty', () {
      final s = PowerState.initial().copyWith(
        availableModes: [const PowerMode('quiet')],
      );
      expect(s.hasLoaded, isTrue);
    });

    test('true when cpuOverclockEnabled is set', () {
      final s = PowerState.initial().copyWith(cpuOverclockEnabled: false);
      expect(s.hasLoaded, isTrue);
    });
  });

  group('PowerState.copyWith sentinel', () {
    test('copyWith with no args returns equal state', () {
      expect(PowerState.initial().copyWith(), equals(PowerState.initial()));
    });

    test('copyWith(currentMode: null) clears mode', () {
      final s = PowerState.initial()
          .copyWith(currentMode: const PowerMode('quiet'))
          .copyWith(currentMode: null);
      expect(s.currentMode, isNull);
    });

    test('copyWith omitting currentMode preserves it', () {
      final mode = const PowerMode('performance');
      final s = PowerState.initial()
          .copyWith(currentMode: mode)
          .copyWith(isLoading: true);
      expect(s.currentMode, equals(mode));
    });

    test('copyWith(errorMessage: null) clears it', () {
      final s = PowerState.initial().copyWith(errorMessage: 'err').copyWith(
        errorMessage: null,
      );
      expect(s.errorMessage, isNull);
    });
  });

  group('PowerState props', () {
    test('identical initial states are equal', () {
      expect(PowerState.initial(), equals(PowerState.initial()));
    });

    test('differ by currentMode', () {
      final a = PowerState.initial().copyWith(
        currentMode: const PowerMode('quiet'),
      );
      final b = PowerState.initial().copyWith(
        currentMode: const PowerMode('balanced'),
      );
      expect(a, isNot(equals(b)));
    });
  });
}
