import 'package:equatable/equatable.dart';

class LiveSensorSnapshot extends Equatable {
  const LiveSensorSnapshot({
    required this.cpuName,
    required this.cpuTempC,
    required this.cpuUtilPercent,
    required this.cpuClockGhz,
    required this.cpuPackagePowerW,
    required this.fan1Rpm,
    required this.fan2Rpm,
    required this.gpuName,
    required this.gpuTempC,
    required this.gpuUtilPercent,
    required this.gpuClockGhz,
    required this.gpuVramUsedGb,
    required this.gpuVramTotalGb,
    required this.gpuFanRpm,
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
    fan2Rpm: null,
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
  final int? fan2Rpm;

  // Active GPU (dGPU when active, iGPU otherwise).
  final String? gpuName;
  final double? gpuTempC;
  final double? gpuUtilPercent;
  final double? gpuClockGhz;
  final double? gpuVramUsedGb;
  final double? gpuVramTotalGb;
  final int? gpuFanRpm;
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
    fan2Rpm,
    gpuName,
    gpuTempC,
    gpuUtilPercent,
    gpuClockGhz,
    gpuVramUsedGb,
    gpuVramTotalGb,
    gpuFanRpm,
    gpuPowerDrawW,
    gpuIsDiscrete,
    motherboardTempC,
    batteryPercent,
    batteryCharging,
    batteryPowerDrawW,
    diskTempC,
  ];
}
