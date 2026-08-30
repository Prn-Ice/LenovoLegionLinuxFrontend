// lib/features/analytics/repository/analytics_repository.dart
import 'package:hive_ce/hive.dart';

import '../../../core/services/legion_sysfs_service.dart';
import '../../../core/services/nvidia_smi_service.dart';
import '../models/sensor_record.dart';

class AnalyticsRepository {
  const AnalyticsRepository({
    required LegionSysfsService sysfsService,
    required NvidiaSmiService nvidiaSmiService,
    required Box<SensorRecord> box,
    Duration retention = const Duration(days: 30),
  }) : _sysfsService = sysfsService,
       _nvidiaSmiService = nvidiaSmiService,
       _box = box,
       _retention = retention;

  final LegionSysfsService _sysfsService;
  final NvidiaSmiService _nvidiaSmiService;
  final Box<SensorRecord> _box;
  final Duration _retention;

  /// Read telemetry in parallel and persist one aligned sample.
  Future<SensorRecord> recordReading() async {
    final results = await Future.wait([
      _sysfsService.readFan1Rpm(),
      _sysfsService.readFan2Rpm(),
      _sysfsService.readCpuTempC(),
      _sysfsService.readGpuTempC(),
      _sysfsService.readBatteryPercent(),
      _sysfsService.readBatteryPowerDrawW(),
      _sysfsService.readBatteryTempC(),
      _nvidiaSmiService.readSnapshot(),
    ]);
    final nvidia = results[7] as NvidiaSmiSnapshot?;
    final record = SensorRecord(
      timestamp: DateTime.now(),
      fan1Rpm: results[0] as int?,
      fan2Rpm: results[1] as int?,
      cpuTempC: results[2] as double?,
      gpuTempC: nvidia?.tempC ?? results[3] as double?,
      batteryPercent: results[4] as int?,
      batteryPowerDrawW: results[5] as double?,
      batteryTempC: results[6] as double?,
      gpuUtilPercent: nvidia?.utilPercent,
      gpuPowerDrawW: nvidia?.powerDrawW,
    );
    await _box.add(record);
    return record;
  }

  /// Return all records with timestamp >= [since], sorted oldest-first.
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
