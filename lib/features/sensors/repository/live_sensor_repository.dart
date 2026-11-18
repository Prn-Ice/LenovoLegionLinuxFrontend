import '../../../core/models/gpu_reading.dart';
import '../../../core/services/igpu_sysfs_service.dart';
import '../../../core/services/legion_sysfs_service.dart';
import '../../../core/services/nvidia_smi_service.dart';
import '../../../core/services/package_power_telemetry_service.dart';
import '../models/live_sensor_snapshot.dart';

class LiveSensorRepository {
  const LiveSensorRepository({
    required LegionSysfsService sysfsService,
    required NvidiaSmiService nvidiaSmiService,
    required IgpuSysfsService igpuSysfsService,
    required PackagePowerTelemetryClient packagePowerTelemetryClient,
  }) : _sysfs = sysfsService,
       _nvidia = nvidiaSmiService,
       _igpu = igpuSysfsService,
       _packagePowerTelemetry = packagePowerTelemetryClient;

  final LegionSysfsService _sysfs;
  final NvidiaSmiService _nvidia;
  final IgpuSysfsService _igpu;
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
      _igpu.readSnapshot(),
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
    final nvidia = results[12] as GpuReading?;
    final igpu = results[13] as GpuReading?;

    final batteryPercent = await _sysfs.readBatteryPercent();
    final batteryStatusStr = await _sysfs.readBatteryStatus();

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
      igpu: igpu,
      dgpu: nvidia,
      motherboardTempC: moboTemp,
      batteryPercent: batteryPercent,
      batteryCharging: batteryStatusStr == null
          ? null
          : batteryStatusStr == 'Charging',
      batteryPowerDrawW: batteryDraw,
      diskTempC: diskTemp,
    );
  }
}
