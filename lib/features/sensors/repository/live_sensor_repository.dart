import '../../../core/models/gpu_process_scan.dart';
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

  Future<LiveSensorSnapshot> loadSnapshot({
    void Function(LiveSensorSnapshot)? onReading,
  }) async {
    String? cpuName;
    double? cpuTempC;
    double? cpuUtil;
    double? cpuClock;
    double? cpuPackagePower;
    int? fan1;
    int? fan1Max;
    int? fan2;
    int? fan2Max;
    int? fan3;
    int? fan3Max;
    double? moboTemp;
    double? batteryDraw;
    double? diskTemp;
    int? batteryPercent;
    bool? batteryCharging;
    GpuReading? nvidia;
    GpuReading? igpu;
    GpuProcessScan? igpuProcesses;

    LiveSensorSnapshot snapshot() => LiveSensorSnapshot(
      cpuName: cpuName,
      cpuTempC: cpuTempC,
      cpuUtilPercent: cpuUtil,
      cpuClockGhz: cpuClock,
      cpuPackagePowerW: cpuPackagePower,
      fan1Rpm: fan1,
      fan1MaxRpm: fan1Max,
      fan2Rpm: fan2,
      fan2MaxRpm: fan2Max,
      fan3Rpm: fan3,
      fan3MaxRpm: fan3Max,
      igpu: igpu,
      igpuProcesses: igpuProcesses,
      dgpu: nvidia,
      motherboardTempC: moboTemp,
      batteryPercent: batteryPercent,
      batteryCharging: batteryCharging,
      batteryPowerDrawW: batteryDraw,
      diskTempC: diskTemp,
    );

    Future<void> read<T>(Future<T> result, void Function(T) record) async {
      record(await result);
      onReading?.call(snapshot());
    }

    await Future.wait([
      read(_sysfs.readCpuName(), (value) => cpuName = value),
      read(_sysfs.readCpuTempC(), (value) => cpuTempC = value),
      read(_sysfs.readCpuUtilisationPercent(), (value) => cpuUtil = value),
      read(_sysfs.readAverageCpuClockGhz(), (value) => cpuClock = value),
      read(
        _packagePowerTelemetry.readPackagePowerWatts(),
        (value) => cpuPackagePower = value,
      ),
      read(_sysfs.readFan1Rpm(), (value) => fan1 = value),
      read(_sysfs.readFan1MaxRpm(), (value) => fan1Max = value),
      read(_sysfs.readFan2Rpm(), (value) => fan2 = value),
      read(_sysfs.readFan2MaxRpm(), (value) => fan2Max = value),
      read(_sysfs.readFan3Rpm(), (value) => fan3 = value),
      read(_sysfs.readFan3MaxRpm(), (value) => fan3Max = value),
      read(_sysfs.readMotherboardTempC(), (value) => moboTemp = value),
      read(_sysfs.readBatteryPowerDrawW(), (value) => batteryDraw = value),
      read(_sysfs.readDiskTempC(), (value) => diskTemp = value),
      read(_sysfs.readBatteryPercent(), (value) => batteryPercent = value),
      read(
        _sysfs.readBatteryStatus(),
        (value) => batteryCharging = value == null ? null : value == 'Charging',
      ),
      read(_nvidia.readSnapshot(), (value) => nvidia = value),
      read(_igpu.readSnapshot(), (value) => igpu = value),
      read(_igpu.readProcesses(), (value) => igpuProcesses = value),
    ]);
    return snapshot();
  }
}
