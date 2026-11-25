import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/models/gpu_reading.dart';
import 'package:hive_ce/hive.dart';
import 'package:legion_frontend/core/services/igpu_sysfs_service.dart';
import 'package:legion_frontend/core/services/legion_sysfs_service.dart';
import 'package:legion_frontend/core/services/nvidia_smi_service.dart';
import 'package:legion_frontend/features/analytics/models/sensor_record.dart';
import 'package:legion_frontend/features/analytics/models/sensor_records_csv.dart';
import 'package:legion_frontend/features/analytics/repository/analytics_repository.dart';
import 'package:mocktail/mocktail.dart';

class MockSysfsService extends Mock implements LegionSysfsService {}

class MockNvidiaSmiService extends Mock implements NvidiaSmiService {}

class MockIgpuSysfsService extends Mock implements IgpuSysfsService {}

/// Older wire formats: fields 0–9, or 0–10 with dGPU temperature.
///
/// This adapter exists only to create a real legacy fixture on disk. Production
/// reads use the generated SensorRecordAdapter below.
class _LegacySensorRecordAdapter extends TypeAdapter<SensorRecord> {
  const _LegacySensorRecordAdapter({this.includeDgpu = false});

  final bool includeDgpu;

  @override
  final typeId = 1;

  @override
  SensorRecord read(BinaryReader reader) {
    final fieldCount = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < fieldCount; i++) reader.readByte(): reader.read(),
    };
    return SensorRecord(
      timestamp: fields[0] as DateTime,
      fan1Rpm: (fields[1] as num?)?.toInt(),
      fan2Rpm: (fields[2] as num?)?.toInt(),
      cpuTempC: (fields[3] as num?)?.toDouble(),
      gpuTempC: (fields[4] as num?)?.toDouble(),
      batteryPercent: (fields[5] as num?)?.toInt(),
      batteryPowerDrawW: (fields[6] as num?)?.toDouble(),
      batteryTempC: (fields[7] as num?)?.toDouble(),
      gpuUtilPercent: (fields[8] as num?)?.toDouble(),
      gpuPowerDrawW: (fields[9] as num?)?.toDouble(),
      dgpuTempC: (fields[10] as num?)?.toDouble(),
    );
  }

  @override
  void write(BinaryWriter writer, SensorRecord obj) {
    writer
      ..writeByte(includeDgpu ? 11 : 10)
      ..writeByte(0)
      ..write(obj.timestamp)
      ..writeByte(1)
      ..write(obj.fan1Rpm)
      ..writeByte(2)
      ..write(obj.fan2Rpm)
      ..writeByte(3)
      ..write(obj.cpuTempC)
      ..writeByte(4)
      ..write(obj.gpuTempC)
      ..writeByte(5)
      ..write(obj.batteryPercent)
      ..writeByte(6)
      ..write(obj.batteryPowerDrawW)
      ..writeByte(7)
      ..write(obj.batteryTempC)
      ..writeByte(8)
      ..write(obj.gpuUtilPercent)
      ..writeByte(9)
      ..write(obj.gpuPowerDrawW);
    if (includeDgpu) {
      writer
        ..writeByte(10)
        ..write(obj.dgpuTempC);
    }
  }
}

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
    when(() => sysfs.readFan3Rpm()).thenAnswer((_) async => null);
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
    expect(box.values.first.fan3Rpm, isNull);
    expect(box.values.first.cpuTempC, 55.0);
    expect(box.values.first.gpuTempC, 48.0);
    expect(box.values.first.dgpuTempC, isNull);
    expect(box.values.first.batteryPercent, 74);
    expect(box.values.first.batteryPowerDrawW, 12.4);
  });

  test('persists attributed dGPU temperature without relabelling legacy GPU records', () async {
    await box.add(SensorRecord(timestamp: DateTime.now(), gpuTempC: 48));
    when(nvidia.readSnapshot)
        .thenAnswer((_) async => const GpuReading(tempC: 67, usagePercent: 31));
    final record = await repo.recordReading();
    expect(record.dgpuTempC, 67);
    expect(record.gpuUtilPercent, 31);
    await box.close();
    box = await Hive.openBox<SensorRecord>('sensor_records_test');
    expect(box.values.first.gpuTempC, 48);
    expect(box.values.first.dgpuTempC, isNull);
    expect(box.values.last.dgpuTempC, 67);
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

  for (final includeDgpu in [false, true]) {
    test(
      'reopens older records with dGPU field: $includeDgpu and new fan records',
      () async {
        final legacyTimestamp = DateTime.now().subtract(
          const Duration(minutes: 2),
        );

        // Persist each released wire format before loading the current adapter.
        await Hive.close();
        Hive.registerAdapter(
          _LegacySensorRecordAdapter(includeDgpu: includeDgpu),
          override: true,
        );
        final legacyBox = await Hive.openBox<SensorRecord>(
          'sensor_records_test',
        );
        await legacyBox.add(
          SensorRecord(
            timestamp: legacyTimestamp,
            fan1Rpm: 1800,
            fan2Rpm: 1700,
            cpuTempC: 61.5,
            batteryPercent: 80,
            dgpuTempC: 58.5,
          ),
        );

        // Reopen with the generated current adapter and persist a fan3 sample.
        await Hive.close();
        Hive.registerAdapter(SensorRecordAdapter(), override: true);
        box = await Hive.openBox<SensorRecord>('sensor_records_test');
        final currentTimestamp = DateTime.now().subtract(
          const Duration(minutes: 1),
        );
        await box.add(
          SensorRecord(
            timestamp: currentTimestamp,
            fan1Rpm: 1900,
            fan2Rpm: 1750,
            fan3Rpm: 2300,
            cpuTempC: 62.5,
            dgpuTempC: 63.5,
          ),
        );

        // A second close/reopen proves both records survive the process boundary.
        await Hive.close();
        Hive.registerAdapter(SensorRecordAdapter(), override: true);
        box = await Hive.openBox<SensorRecord>('sensor_records_test');
        repo = AnalyticsRepository(
          sysfsService: sysfs,
          nvidiaSmiService: nvidia,
          box: box,
        );
        final history = repo.readHistory(
          since: DateTime.now().subtract(const Duration(minutes: 5)),
        );

        expect(history, hasLength(2));
        expect(history.first.fan3Rpm, isNull);
        expect(history.first.dgpuTempC, includeDgpu ? 58.5 : null);
        expect(history.first.fan1Rpm, 1800);
        expect(history.first.cpuTempC, 61.5);
        expect(history.first.batteryPercent, 80);
        expect(history.last.fan3Rpm, 2300);
        expect(history.last.dgpuTempC, 63.5);
        expect(history.last.fan2Rpm, 1750);

        final csv = utf8.decode(sensorRecordsCsv(history));
        expect(csv, contains('1800,1700,'));
        expect(csv, contains('1900,1750,63.5,2300'));
      },
    );
  }

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

  test(
    'records integrated GPU usage and temperature when NVIDIA is absent',
    () async {
      final igpu = MockIgpuSysfsService();
      when(() => nvidia.readSnapshot()).thenAnswer((_) async => null);
      when(() => igpu.readSnapshot()).thenAnswer(
        (_) async => const GpuReading(
          name: 'AMD Integrated Graphics',
          usagePercent: 18,
          tempC: 44.5,
        ),
      );
      final igpuRepo = AnalyticsRepository(
        sysfsService: sysfs,
        nvidiaSmiService: nvidia,
        igpuSysfsService: igpu,
        box: box,
      );

      final record = await igpuRepo.recordReading();

      expect(record.dgpuTempC, isNull);
      expect(record.gpuUtilPercent, isNull);
      expect(record.igpuTempC, 44.5);
      expect(record.igpuUtilPercent, 18);
      expect(record.gpuTempC, 44.5);
    },
  );
}
