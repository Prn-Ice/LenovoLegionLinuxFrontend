// test/features/analytics/analytics_repository_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:legion_frontend/core/services/legion_sysfs_service.dart';
import 'package:legion_frontend/core/services/nvidia_smi_service.dart';
import 'package:legion_frontend/features/analytics/models/sensor_record.dart';
import 'package:legion_frontend/features/analytics/repository/analytics_repository.dart';
import 'package:mocktail/mocktail.dart';

class MockSysfsService extends Mock implements LegionSysfsService {}

class MockNvidiaSmiService extends Mock implements NvidiaSmiService {}

void main() {
  late Directory tmpDir;
  late MockSysfsService sysfs;
  late AnalyticsRepository repo;
  late MockNvidiaSmiService nvidia;
  late Box<SensorRecord> box;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('hive_test_');
    Hive.init(tmpDir.path);
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(SensorRecordAdapter());
    }
    box = await Hive.openBox<SensorRecord>('sensor_records_test');

    sysfs = MockSysfsService();
    when(() => sysfs.readFan1Rpm()).thenAnswer((_) async => 2500);
    when(() => sysfs.readFan2Rpm()).thenAnswer((_) async => 2200);
    when(() => sysfs.readCpuTempC()).thenAnswer((_) async => 55.0);
    when(() => sysfs.readGpuTempC()).thenAnswer((_) async => 48.0);
    when(() => sysfs.readBatteryPercent()).thenAnswer((_) async => 74);
    when(() => sysfs.readBatteryPowerDrawW()).thenAnswer((_) async => 12.4);
    when(() => sysfs.readBatteryTempC()).thenAnswer((_) async => 29.5);
    nvidia = MockNvidiaSmiService();
    when(() => nvidia.readSnapshot()).thenAnswer((_) async => null);

    repo = AnalyticsRepository(
      sysfsService: sysfs,
      nvidiaSmiService: nvidia,
      box: box,
    );
  });

  tearDown(() async {
    await Hive.close();
    await tmpDir.delete(recursive: true);
  });

  test('recordReading persists a SensorRecord to Hive', () async {
    await repo.recordReading();
    expect(box.length, 1);
    expect(box.values.first.fan1Rpm, 2500);
    expect(box.values.first.fan2Rpm, 2200);
    expect(box.values.first.cpuTempC, 55.0);
    expect(box.values.first.gpuTempC, 48.0);
    expect(box.values.first.batteryPercent, 74);
    expect(box.values.first.batteryPowerDrawW, 12.4);
  });

  test('readHistory returns all records within the window', () async {
    await repo.recordReading();
    final history = repo.readHistory(
      since: DateTime.now().subtract(const Duration(hours: 1)),
    );
    expect(history.length, 1);
  });

  test('readHistory excludes records outside the window', () async {
    // Add a record that is outside the window via direct box access
    await box.add(
      SensorRecord(
        timestamp: DateTime.now().subtract(const Duration(hours: 2)),
        fan1Rpm: 999,
      ),
    );
    final history = repo.readHistory(
      since: DateTime.now().subtract(const Duration(hours: 1)),
    );
    expect(history, isEmpty);
  });

  test('pruneOldRecords removes records older than retention', () async {
    await box.add(
      SensorRecord(
        timestamp: DateTime.now().subtract(const Duration(days: 31)),
        fan1Rpm: 999,
      ),
    );
    await repo.pruneOldRecords();
    expect(box.length, 0);
  });

  test('pruneOldRecords keeps records within retention', () async {
    await repo.recordReading();
    await repo.pruneOldRecords();
    expect(box.length, 1);
  });
}
