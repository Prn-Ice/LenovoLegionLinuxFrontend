import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/sensors/models/live_sensor_snapshot.dart';

void main() {
  group('LiveSensorSnapshot', () {
    test('initial has all nulls', () {
      final s = LiveSensorSnapshot.initial();
      expect(s.cpuName, isNull);
      expect(s.cpuTempC, isNull);
      expect(s.cpuPackagePowerW, isNull);
      expect(s.fan1Rpm, isNull);
      expect(s.batteryPercent, isNull);
    });

    test('equality holds when all fields match', () {
      final a = LiveSensorSnapshot(
        cpuName: 'Ryzen 7',
        cpuTempC: 61.0,
        cpuUtilPercent: 12.0,
        cpuClockGhz: 3.1,
        cpuPackagePowerW: 24.5,
        fan1Rpm: 1800,
        fan2Rpm: 1500,
        gpuName: null,
        gpuTempC: null,
        gpuUtilPercent: null,
        gpuClockGhz: null,
        gpuVramUsedGb: null,
        gpuVramTotalGb: null,
        gpuFanRpm: null,
        gpuPowerDrawW: null,
        gpuIsDiscrete: false,
        motherboardTempC: null,
        batteryPercent: 78,
        batteryCharging: true,
        batteryPowerDrawW: -18.0,
        diskTempC: null,
      );
      final b = a;
      expect(a, equals(b));
    });

    test('gpuIsDiscrete defaults to false', () {
      expect(LiveSensorSnapshot.initial().gpuIsDiscrete, isFalse);
    });
  });
}
