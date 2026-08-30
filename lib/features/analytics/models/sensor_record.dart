// lib/features/analytics/models/sensor_record.dart
import 'package:hive_ce/hive.dart';

part 'sensor_record.g.dart';

@HiveType(typeId: 1)
class SensorRecord extends HiveObject {
  SensorRecord({
    required this.timestamp,
    this.fan1Rpm,
    this.fan2Rpm,
    this.cpuTempC,
    this.gpuTempC,
    this.batteryPercent,
    this.batteryPowerDrawW,
    this.batteryTempC,
    this.gpuUtilPercent,
    this.gpuPowerDrawW,
  });

  @HiveField(0)
  DateTime timestamp;

  @HiveField(1)
  int? fan1Rpm;

  @HiveField(2)
  int? fan2Rpm;

  @HiveField(3)
  double? cpuTempC;

  @HiveField(4)
  double? gpuTempC;

  @HiveField(5)
  int? batteryPercent;

  @HiveField(6)
  double? batteryPowerDrawW;

  @HiveField(7)
  double? batteryTempC;

  @HiveField(8)
  double? gpuUtilPercent;

  @HiveField(9)
  double? gpuPowerDrawW;
}
