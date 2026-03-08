// test/core/services/legion_sysfs_service_analytics_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/services/legion_sysfs_service.dart';

void main() {
  late Directory tmpDir;
  late LegionSysfsService service;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('sysfs_test_');
    service = LegionSysfsService();
  });

  tearDown(() async => tmpDir.delete(recursive: true));

  group('parseFanRpm', () {
    test('returns RPM when file contains valid integer', () async {
      await File('${tmpDir.path}/fan1_input').writeAsString('3200\n');
      expect(await service.readIntFile('${tmpDir.path}/fan1_input'), 3200);
    });

    test('returns null when file does not exist', () async {
      expect(await service.readIntFile('${tmpDir.path}/nonexistent'), isNull);
    });
  });

  group('milliDegreesToC', () {
    test('converts millidegrees to degrees', () {
      expect(LegionSysfsService.milliDegreesToC(45000), 45.0);
      expect(LegionSysfsService.milliDegreesToC(72500), 72.5);
    });
  });
}
