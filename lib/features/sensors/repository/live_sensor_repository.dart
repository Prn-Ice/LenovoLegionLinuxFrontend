import 'dart:io';

import '../../../core/services/legion_sysfs_service.dart';
import '../../../core/services/nvidia_smi_service.dart';
import '../../../core/services/package_power_telemetry_service.dart';
import '../models/live_sensor_snapshot.dart';

class LiveSensorRepository {
  const LiveSensorRepository({
    required LegionSysfsService sysfsService,
    required NvidiaSmiService nvidiaSmiService,
    required PackagePowerTelemetryClient packagePowerTelemetryClient,
  }) : _sysfs = sysfsService,
       _nvidia = nvidiaSmiService,
       _packagePowerTelemetry = packagePowerTelemetryClient;

  final LegionSysfsService _sysfs;
  final NvidiaSmiService _nvidia;
  final PackagePowerTelemetryClient _packagePowerTelemetry;

  Future<LiveSensorSnapshot> loadSnapshot() async {
    final results = await Future.wait([
      _sysfs.readCpuName(),
      _sysfs.readCpuTempC(),
      _sysfs.readCpuUtilisationPercent(),
      _sysfs.readAverageCpuClockGhz(),
      _packagePowerTelemetry.readPackagePowerWatts(),
      _sysfs.readFan1Rpm(),
      _sysfs.readFan1MaxRpm(),
      _sysfs.readFan2Rpm(),
      _sysfs.readFan2MaxRpm(),
      _sysfs.readMotherboardTempC(),
      _sysfs.readBatteryPowerDrawW(),
      _sysfs.readDiskTempC(),
      _nvidia.readSnapshot(),
    ]);

    final cpuName = results[0] as String?;
    final cpuTempC = results[1] as double?;
    final cpuUtil = results[2] as double?;
    final cpuClock = results[3] as double?;
    final cpuPackagePower = results[4] as double?;
    final fan1 = results[5] as int?;
    final fan1Max = results[6] as int?;
    final fan2 = results[7] as int?;
    final fan2Max = results[8] as int?;
    final moboTemp = results[9] as double?;
    final batteryDraw = results[10] as double?;
    final diskTemp = results[11] as double?;
    final nvidia = results[12] as NvidiaSmiSnapshot?;

    // Battery percent from sysfs.
    final batteryPercent = await _sysfs.readIntFile(
      '/sys/class/power_supply/BAT0/capacity',
    );
    // Read charging state directly.
    final batteryStatusStr = await _readBatteryStatus();

    if (nvidia != null) {
      // dGPU is active.
      return LiveSensorSnapshot(
        cpuName: cpuName,
        cpuTempC: cpuTempC,
        cpuUtilPercent: cpuUtil,
        cpuClockGhz: cpuClock,
        cpuPackagePowerW: cpuPackagePower,
        fan1Rpm: fan1,
        fan1MaxRpm: fan1Max,
        fan2Rpm: fan2,
        fan2MaxRpm: fan2Max,
        gpuName: nvidia.name,
        gpuTempC: nvidia.tempC,
        gpuUtilPercent: nvidia.utilPercent,
        gpuClockGhz: nvidia.clkGhz,
        gpuVramUsedGb: nvidia.vramUsedGb,
        gpuVramTotalGb: nvidia.vramTotalGb,
        gpuFanPercent: nvidia.fanPercent,
        gpuPowerDrawW: nvidia.powerDrawW,
        gpuIsDiscrete: true,
        gpuPerformanceState: nvidia.performanceState,
        motherboardTempC: moboTemp,
        batteryPercent: batteryPercent,
        batteryCharging: batteryStatusStr == null
            ? null
            : batteryStatusStr == 'Charging',
        batteryPowerDrawW: batteryDraw,
        diskTempC: diskTemp,
      );
    }

    // iGPU fallback — use existing sysfs GPU temp.
    final igpuTemp = await _sysfs.readGpuTempC();
    return LiveSensorSnapshot(
      cpuName: cpuName,
      cpuTempC: cpuTempC,
      cpuUtilPercent: cpuUtil,
      cpuClockGhz: cpuClock,
      cpuPackagePowerW: cpuPackagePower,
      fan1Rpm: fan1,
      fan1MaxRpm: fan1Max,
      fan2Rpm: fan2,
      fan2MaxRpm: fan2Max,
      gpuName: null,
      gpuTempC: igpuTemp,
      gpuUtilPercent: null,
      gpuClockGhz: null,
      gpuVramUsedGb: null,
      gpuVramTotalGb: null,
      gpuFanPercent: null,
      gpuPowerDrawW: null,
      gpuIsDiscrete: false,
      gpuPerformanceState: null,
      motherboardTempC: moboTemp,
      batteryPercent: batteryPercent,
      batteryCharging: batteryStatusStr == null
          ? null
          : batteryStatusStr == 'Charging',
      batteryPowerDrawW: batteryDraw,
      diskTempC: diskTemp,
    );
  }

  Future<String?> _readBatteryStatus() async {
    try {
      final file = File('/sys/class/power_supply/BAT0/status');
      if (!await file.exists()) return null;
      return (await file.readAsString()).trim();
    } catch (_) {
      return null;
    }
  }
}
