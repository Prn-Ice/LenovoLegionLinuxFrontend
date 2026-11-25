import 'package:hive_ce/hive.dart';

import '../../../core/models/gpu_reading.dart';
import '../../../core/services/igpu_sysfs_service.dart';
import '../../../core/services/legion_sysfs_service.dart';
import '../../../core/services/nvidia_smi_service.dart';
import '../models/sensor_record.dart';

class AnalyticsRepository {
  const AnalyticsRepository({
    required this._sysfsService,
    required this._nvidiaSmiService,
    this._igpuSysfsService,
    required this._box,
    this._retention = const Duration(days: 30),
  });

  final LegionSysfsService _sysfsService;
  final NvidiaSmiService _nvidiaSmiService;
  final IgpuSysfsService? _igpuSysfsService;
  final Box<SensorRecord> _box;
  final Duration _retention;

  /// Read telemetry in parallel and persist one aligned sample.
  Future<SensorRecord> recordReading() async {
    final results = await Future.wait([
      _sysfsService.readFan1Rpm(),
      _sysfsService.readFan2Rpm(),
      _sysfsService.readFan3Rpm(),
      _sysfsService.readCpuTempC(),
      _sysfsService.readGpuTempC(),
      _sysfsService.readBatteryPercent(),
      _sysfsService.readBatteryPowerDrawW(),
      _sysfsService.readBatteryTempC(),
      _nvidiaSmiService.readSnapshot(),
      _igpuSysfsService?.readSnapshot() ?? Future<GpuReading?>.value(null),
    ]);
    final nvidia = results[8] as GpuReading?;
    final igpu = results[9] as GpuReading?;
    final record = SensorRecord(
      timestamp: DateTime.now(),
      fan1Rpm: results[0] as int?,
      fan2Rpm: results[1] as int?,
      fan3Rpm: results[2] as int?,
      cpuTempC: results[3] as double?,
      gpuTempC: nvidia?.tempC ?? igpu?.tempC ?? results[4] as double?,
      batteryPercent: results[5] as int?,
      batteryPowerDrawW: results[6] as double?,
      batteryTempC: results[7] as double?,
      gpuUtilPercent: nvidia?.usagePercent,
      gpuPowerDrawW: nvidia?.powerDrawW,
      dgpuTempC: nvidia?.tempC,
      igpuTempC: igpu?.tempC,
      igpuUtilPercent: igpu?.usagePercent,
    );
    await _box.add(record);
    return record;
  }

  /// Return records newer than [since], oldest first.
  List<SensorRecord> readHistory({required DateTime since}) {
    return _box.values.where((r) => r.timestamp.isAfter(since)).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  /// Delete records older than [_retention]. Call on startup and periodically.
  Future<void> pruneOldRecords() async {
    final cutoff = DateTime.now().subtract(_retention);
    final stale = _box.values
        .where((r) => r.timestamp.isBefore(cutoff))
        .toList();
    for (final record in stale) {
      await record.delete();
    }
  }
}
