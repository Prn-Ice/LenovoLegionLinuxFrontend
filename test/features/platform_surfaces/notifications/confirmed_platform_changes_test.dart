import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/fans/bloc/fans_state.dart';
import 'package:legion_frontend/features/platform_surfaces/models/platform_event.dart';
import 'package:legion_frontend/features/platform_surfaces/notifications/confirmed_platform_changes.dart';
import 'package:legion_frontend/features/power/bloc/power_state.dart';
import 'package:legion_frontend/features/power/models/power_mode.dart';

void main() {
  test(
    'power baseline, busy readback, confirmed completion, errors and unknown',
    () {
      final changes = ConfirmedPlatformChanges();
      final quiet = PowerState.initial().copyWith(
        currentMode: const PowerMode('quiet'),
      );
      final performance = quiet.copyWith(
        currentMode: const PowerMode('performance'),
      );
      expect(changes.observePower(quiet), isNull);
      expect(
        changes.observePower(performance.copyWith(isApplying: true)),
        isNull,
      );
      expect(
        changes.observePower(
          performance.copyWith(errorMessage: 'readback failed'),
        ),
        isNull,
      );
      expect(
        changes.observePower(performance),
        isA<PowerModeChanged>().having(
          (event) => event.label,
          'label',
          'Performance',
        ),
      );
      expect(changes.observePower(performance), isNull);
      expect(changes.observePower(PowerState.initial()), isNull);
      expect(changes.observePower(quiet), isNull);
    },
  );

  test('fan boost only reports known stable changes, not first load', () {
    final changes = ConfirmedPlatformChanges();
    final off = FansState.initial().copyWith(maximumFanSpeedEnabled: false);
    final on = off.copyWith(maximumFanSpeedEnabled: true);
    expect(changes.observeFans(off), isNull);
    expect(changes.observeFans(on.copyWith(isLoading: true)), isNull);
    expect(
      changes.observeFans(on),
      isA<FanBoostChanged>().having((event) => event.enabled, 'enabled', true),
    );
    expect(changes.observeFans(on), isNull);
  });
}
