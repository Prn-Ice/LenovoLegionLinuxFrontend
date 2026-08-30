import 'dart:convert';
import 'dart:typed_data';

import 'sensor_record.dart';

Uint8List sensorRecordsCsv(List<SensorRecord> records) {
  String cell(Object? value) => value == null ? '' : '$value';

  final rows = <List<String>>[
    const [
      'timestamp',
      'battery_percent',
      'battery_power_w',
      'battery_temp_c',
      'gpu_util_percent',
      'gpu_power_w',
      'gpu_temp_c',
      'cpu_temp_c',
      'fan1_rpm',
      'fan2_rpm',
    ],
    for (final record in records)
      [
        record.timestamp.toIso8601String(),
        cell(record.batteryPercent),
        cell(record.batteryPowerDrawW),
        cell(record.batteryTempC),
        cell(record.gpuUtilPercent),
        cell(record.gpuPowerDrawW),
        cell(record.gpuTempC),
        cell(record.cpuTempC),
        cell(record.fan1Rpm),
        cell(record.fan2Rpm),
      ],
  ];

  return Uint8List.fromList(
    utf8.encode(rows.map((row) => row.join(',')).join('\n')),
  );
}
