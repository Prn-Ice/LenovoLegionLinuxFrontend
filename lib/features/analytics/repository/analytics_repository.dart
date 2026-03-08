// lib/features/analytics/repository/analytics_repository.dart
import 'package:hive_ce/hive.dart';

import '../../../core/services/legion_sysfs_service.dart';
import '../models/sensor_record.dart';

class AnalyticsRepository {
  const AnalyticsRepository({
    required LegionSysfsService sysfsService,
    required Box<SensorRecord> box,
    Duration retention = const Duration(days: 30),
  }) : _sysfsService = sysfsService,
       _box = box,
       _retention = retention;

  final LegionSysfsService _sysfsService;
  final Box<SensorRecord> _box;
  final Duration _retention;

  /// Read all four sensors in parallel and persist the result.
  Future<SensorRecord> recordReading() async {
    final results = await Future.wait([
      _sysfsService.readFan1Rpm(),
      _sysfsService.readFan2Rpm(),
      _sysfsService.readCpuTempC(),
      _sysfsService.readGpuTempC(),
    ]);
    final record = SensorRecord(
      timestamp: DateTime.now(),
      fan1Rpm: results[0] as int?,
      fan2Rpm: results[1] as int?,
      cpuTempC: results[2] as double?,
      gpuTempC: results[3] as double?,
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
