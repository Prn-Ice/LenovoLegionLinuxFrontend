import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/analytics/models/sensor_record.dart';
import 'package:legion_frontend/features/analytics/models/sensor_records_csv.dart';

void main() {
  test('exports battery and dGPU telemetry with stable columns', () {
    final bytes = sensorRecordsCsv([
      SensorRecord(
        timestamp: DateTime.utc(2026, 8, 30, 12),
        batteryPercent: 78,
        batteryPowerDrawW: 14.2,
        batteryTempC: 28.5,
        gpuUtilPercent: 42,
        gpuPowerDrawW: 37.8,
        gpuTempC: 64,
      ),
    ]);
    final csv = utf8.decode(bytes);

    expect(csv, contains('battery_percent,battery_power_w,battery_temp_c'));
    expect(csv, contains('gpu_util_percent,gpu_power_w,gpu_temp_c'));
    expect(
      csv,
      contains('2026-08-30T12:00:00.000Z,78,14.2,28.5,42.0,37.8,64.0'),
    );
  });
}
