import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/battery/bloc/battery_state.dart';

void main() {
  BatteryState state({
    bool? charging = false,
    double? power = 22.818,
    double? current = 39.14,
    double? full = 95.33,
  }) {
    return BatteryState.initial().copyWith(
      batteryCharging: charging,
      batteryPowerDrawW: power,
      currentCapacityWh: current,
      fullCapacityWh: full,
    );
  }

  test('estimates discharging time only on battery', () {
    expect(state().estimatedTimeMinutes(onPowerSupply: false), 103);
    expect(state().estimatedTimeMinutes(onPowerSupply: true), isNull);
  });

  test('estimates charging time to full', () {
    expect(
      state(charging: true).estimatedTimeMinutes(onPowerSupply: true),
      148,
    );
  });

  test('does not estimate connected but not charging', () {
    expect(state().estimatedTimeMinutes(onPowerSupply: true), isNull);
    expect(state().estimatedTimeMinutes(onPowerSupply: null), isNull);
  });

  test('rejects missing, invalid, negligible, and excessive inputs', () {
    expect(
      state(power: null).estimatedTimeMinutes(onPowerSupply: false),
      isNull,
    );
    expect(
      state(
        charging: true,
        full: null,
      ).estimatedTimeMinutes(onPowerSupply: true),
      isNull,
    );
    expect(
      state(power: 0.49).estimatedTimeMinutes(onPowerSupply: false),
      isNull,
    );
    expect(
      state(current: double.nan).estimatedTimeMinutes(onPowerSupply: false),
      isNull,
    );
    expect(
      state(current: 40, power: 0.5).estimatedTimeMinutes(onPowerSupply: false),
      isNull,
    );
    expect(
      state(charging: null).estimatedTimeMinutes(onPowerSupply: false),
      isNull,
    );
  });

  test('formats durations without zero-unit noise', () {
    expect(formatBatteryDuration(20), '20m');
    expect(formatBatteryDuration(120), '2h');
    expect(formatBatteryDuration(140), '2h 20m');
  });
}
