import 'dart:io';

import '../../../core/services/legion_sysfs_service.dart';
import '../../../core/services/nvidia_smi_service.dart';
import '../models/live_sensor_snapshot.dart';

class LiveSensorRepository {
  const LiveSensorRepository({
    required LegionSysfsService sysfsService,
    required NvidiaSmiService nvidiaSmiService,
  })  : _sysfs = sysfsService,
        _nvidia = nvidiaSmiService;

  final LegionSysfsService _sysfs;
  final NvidiaSmiService _nvidia;

  Future<LiveSensorSnapshot> loadSnapshot() async {
    final results = await Future.wait([
      _sysfs.readCpuName(),
      _sysfs.readCpuTempC(),
      _sysfs.readCpuUtilisationPercent(),
      _sysfs.readAverageCpuClockGhz(),
      _sysfs.readFan1Rpm(),
      _sysfs.readFan2Rpm(),
      _sysfs.readMotherboardTempC(),
      _sysfs.readBatteryPowerDrawW(),
      _sysfs.readDiskTempC(),
      _nvidia.readSnapshot(),
    ]);

    final cpuName = results[0] as String?;
    final cpuTempC = results[1] as double?;
    final cpuUtil = results[2] as double?;
    final cpuClock = results[3] as double?;
    final fan1 = results[4] as int?;
    final fan2 = results[5] as int?;
    final moboTemp = results[6] as double?;
    final batteryDraw = results[7] as double?;
    final diskTemp = results[8] as double?;
    final nvidia = results[9] as NvidiaSmiSnapshot?;

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
        fan1Rpm: fan1,
        fan2Rpm: fan2,
        gpuName: nvidia.name,
        gpuTempC: nvidia.tempC,
        gpuUtilPercent: nvidia.utilPercent,
        gpuClockGhz: nvidia.clkGhz,
        gpuVramUsedGb: nvidia.vramUsedGb,
        gpuVramTotalGb: nvidia.vramTotalGb,
        gpuFanRpm: nvidia.fanRpm,
        gpuPowerDrawW: nvidia.powerDrawW,
        gpuIsDiscrete: true,
        motherboardTempC: moboTemp,
        batteryPercent: batteryPercent,
        batteryCharging: batteryStatusStr == null ? null : batteryStatusStr == 'Charging',
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
      fan1Rpm: fan1,
      fan2Rpm: fan2,
      gpuName: null,
      gpuTempC: igpuTemp,
      gpuUtilPercent: null,
      gpuClockGhz: null,
      gpuVramUsedGb: null,
      gpuVramTotalGb: null,
      gpuFanRpm: null,
      gpuPowerDrawW: null,
      gpuIsDiscrete: false,
      motherboardTempC: moboTemp,
      batteryPercent: batteryPercent,
      batteryCharging: batteryStatusStr == null ? null : batteryStatusStr == 'Charging',
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
