import 'package:equatable/equatable.dart';

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
    required this.gpuName,
    required this.gpuTempC,
    required this.gpuUtilPercent,
    required this.gpuClockGhz,
    required this.gpuVramUsedGb,
    required this.gpuVramTotalGb,
    required this.gpuFanPercent,
    required this.gpuPowerDrawW,
    required this.gpuIsDiscrete,
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
    gpuName: null,
    gpuTempC: null,
    gpuUtilPercent: null,
    gpuClockGhz: null,
    gpuVramUsedGb: null,
    gpuVramTotalGb: null,
    gpuFanPercent: null,
    gpuPowerDrawW: null,
    gpuIsDiscrete: false,
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

  // Active GPU (dGPU when active, iGPU otherwise).
  final String? gpuName;
  final double? gpuTempC;
  final double? gpuUtilPercent;
  final double? gpuClockGhz;
  final double? gpuVramUsedGb;
  final double? gpuVramTotalGb;
  final int? gpuFanPercent;
  final double? gpuPowerDrawW;
  final bool gpuIsDiscrete;

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
    gpuName,
    gpuTempC,
    gpuUtilPercent,
    gpuClockGhz,
    gpuVramUsedGb,
    gpuVramTotalGb,
    gpuFanPercent,
    gpuPowerDrawW,
    gpuIsDiscrete,
    motherboardTempC,
    batteryPercent,
    batteryCharging,
    batteryPowerDrawW,
    diskTempC,
  ];
}
