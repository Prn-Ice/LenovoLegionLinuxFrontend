import 'package:equatable/equatable.dart';

import '../../../core/models/gpu_process_scan.dart';
import '../../../core/models/gpu_reading.dart';

class LiveSensorSnapshot extends Equatable {
  const LiveSensorSnapshot({
    required this.cpuName,
    required this.cpuTempC,
    required this.cpuUtilPercent,
    required this.cpuClockGhz,
    required this.cpuPackagePowerW,
    required this.fan1Rpm,
    this.fan1MaxRpm,
    required this.fan2Rpm,
    this.fan2MaxRpm,
    this.fan3Rpm,
    this.fan3MaxRpm,
    this.igpu,
    this.igpuProcesses,
    this.dgpu,
    required this.motherboardTempC,
    required this.batteryPercent,
    required this.batteryCharging,
    required this.batteryPowerDrawW,
    required this.diskTempC,
  });

  factory LiveSensorSnapshot.initial() => const LiveSensorSnapshot(
    cpuName: null,
    cpuTempC: null,
    cpuUtilPercent: null,
    cpuClockGhz: null,
    cpuPackagePowerW: null,
    fan1Rpm: null,
    fan1MaxRpm: null,
    fan2Rpm: null,
    fan2MaxRpm: null,
    fan3Rpm: null,
    fan3MaxRpm: null,
    motherboardTempC: null,
    batteryPercent: null,
    batteryCharging: null,
    batteryPowerDrawW: null,
    diskTempC: null,
  );

  final String? cpuName;
  final double? cpuTempC;
  final double? cpuUtilPercent;
  final double? cpuClockGhz;
  final double? cpuPackagePowerW;
  final int? fan1Rpm;
  final int? fan1MaxRpm;
  final int? fan2Rpm;
  final int? fan2MaxRpm;
  final int? fan3Rpm;
  final int? fan3MaxRpm;

  final GpuReading? igpu;

  /// Kernel-attributed process use for the identified integrated GPU.
  final GpuProcessScan? igpuProcesses;

  final GpuReading? dgpu;

  final double? motherboardTempC;
  final int? batteryPercent;
  final bool? batteryCharging;
  final double? batteryPowerDrawW;
  final double? diskTempC;

  @override
  List<Object?> get props => [
    cpuName,
    cpuTempC,
    cpuUtilPercent,
    cpuClockGhz,
    cpuPackagePowerW,
    fan1Rpm,
    fan1MaxRpm,
    fan2Rpm,
    fan2MaxRpm,
    fan3Rpm,
    fan3MaxRpm,
    igpu,
    igpuProcesses,
    dgpu,
    motherboardTempC,
    batteryPercent,
    batteryCharging,
    batteryPowerDrawW,
    diskTempC,
  ];
}
