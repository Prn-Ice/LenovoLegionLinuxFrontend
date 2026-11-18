import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/services/legion_sysfs_service.dart';
import 'package:legion_frontend/features/fans/models/fan_curve.dart';

void main() {
  late Directory root;
  late Directory hwmonRoot;
  late Directory controllerRoot;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('legion_fan_sysfs_');
    hwmonRoot = Directory('${root.path}/class/hwmon');
    controllerRoot = Directory('${root.path}/controller/hwmon');
    await hwmonRoot.create(recursive: true);
    await controllerRoot.create(recursive: true);
  });

  tearDown(() => root.delete(recursive: true));

  test('rejects unrelated and unnamed fan providers', () async {
    for (final name in ['amdgpu', 'unrelated', '']) {
      final provider = Directory('${hwmonRoot.path}/hwmon${name.length}');
      await provider.create();
      if (name.isNotEmpty) {
        await File('${provider.path}/name').writeAsString(name);
      }
      await File('${provider.path}/fan1_input').writeAsString('9999');
      await File('${provider.path}/fan2_input').writeAsString('8888');
    }
    final service = LegionSysfsService(
      hwmonRoot: hwmonRoot.path,
      fanHwmonRoot: controllerRoot.path,
    );
    expect(await service.readFan1Rpm(), isNull);
    expect(await service.readFan2Rpm(), isNull);
    final yoga = Directory('${hwmonRoot.path}/hwmon20')..createSync();
    File('${yoga.path}/name').writeAsStringSync('yogafan\n');
    File('${yoga.path}/fan1_input').writeAsStringSync('2300');
    File('${yoga.path}/fan2_input').writeAsStringSync('2400');
    File('${yoga.path}/fan3_input').writeAsStringSync('2500');
    expect(await service.readFan1Rpm(), 2300);
    expect(await service.readFan2Rpm(), 2400);
    expect(await service.readFan3Rpm(), isNull);
    final controller = Directory('${controllerRoot.path}/hwmon0')..createSync();
    File('${controller.path}/fan1_input').writeAsStringSync('0');
    File('${controller.path}/fan3_input').writeAsStringSync('2500');
    expect(await service.readFan1Rpm(), 0);
    expect(await service.readFan2Rpm(), 2400);
    expect(await service.readFan3Rpm(), 2500);
  });

  test('follows controller hwmon symlinks for live RPMs', () async {
    final provider = Directory('${hwmonRoot.path}/hwmon0');
    await provider.create();
    await File('${provider.path}/fan1_input').writeAsString('3200\n');
    await Link('${controllerRoot.path}/hwmon0').create(provider.path);

    final service = LegionSysfsService(
      hwmonRoot: hwmonRoot.path,
      fanHwmonRoot: controllerRoot.path,
    );

    expect(await service.readFan1Rpm(), 3200);
  });

  test(
    'falls back to global hwmon providers when controller has no input',
    () async {
      final controller = Directory('${controllerRoot.path}/hwmon0');
      await controller.create();
      final yogafan = Directory('${hwmonRoot.path}/hwmon1');
      await yogafan.create();
      await File('${yogafan.path}/name').writeAsString('yogafan\n');
      await File('${yogafan.path}/fan2_input').writeAsString('4100\n');

      final service = LegionSysfsService(
        hwmonRoot: hwmonRoot.path,
        fanHwmonRoot: controllerRoot.path,
      );

      expect(await service.readFan2Rpm(), 4100);
    },
  );

  test('reads complete curve and propagates channel maxima', () async {
    final controller = Directory('${controllerRoot.path}/hwmon0');
    await controller.create();
    await File('${controller.path}/fan1_max').writeAsString('10000\n');
    await File('${controller.path}/fan2_max').writeAsString('9000\n');
    for (var i = 1; i <= 10; i++) {
      final values = <String, int>{
        'pwm1_auto_point${i}_pwm': i * 20,
        'pwm2_auto_point${i}_pwm': i * 20,
        'pwm1_auto_point${i}_temp_hyst': 3,
        'pwm1_auto_point${i}_temp': 30 + i * 5,
        'pwm2_auto_point${i}_temp_hyst': 3,
        'pwm2_auto_point${i}_temp': 32 + i * 5,
        'pwm3_auto_point${i}_temp_hyst': 2,
        'pwm3_auto_point${i}_temp': 35 + i * 5,
        'pwm1_auto_point${i}_accel': 4,
        'pwm1_auto_point${i}_decel': 8,
      };
      for (final entry in values.entries) {
        await File('${controller.path}/${entry.key}')
            .writeAsString('${entry.value}\n');
      }
    }
    final curve = await LegionSysfsService(
      hwmonRoot: hwmonRoot.path,
      fanHwmonRoot: controllerRoot.path,
    ).readFanCurve();
    expect(curve?.fan1MaxRpm, 10000);
    expect(curve?.fan2MaxRpm, 9000);
    expect(curve?.points.first.fan1Rpm, closeTo(784, 1));
  });

  test(
    'rejects an incomplete curve instead of rendering partial controls',
    () async {
      final controller = Directory('${controllerRoot.path}/hwmon0');
      await controller.create();
      await File('${controller.path}/fan1_max').writeAsString('10000');
      await File('${controller.path}/fan2_max').writeAsString('10000');
      expect(
        await LegionSysfsService(
          hwmonRoot: hwmonRoot.path,
          fanHwmonRoot: controllerRoot.path,
        ).readFanCurve(),
        isNull,
      );
    },
  );

  test('rejects a present but all-zero curve', () async {
    final controller = Directory('${controllerRoot.path}/hwmon0');
    await controller.create();
    await File('${controller.path}/fan1_max').writeAsString('10000');
    await File('${controller.path}/fan2_max').writeAsString('10000');
    for (var i = 1; i <= 10; i++) {
      for (final field in [
        'pwm1_auto_point${i}_pwm',
        'pwm2_auto_point${i}_pwm',
        'pwm1_auto_point${i}_temp_hyst',
        'pwm1_auto_point${i}_temp',
        'pwm2_auto_point${i}_temp_hyst',
        'pwm2_auto_point${i}_temp',
        'pwm3_auto_point${i}_temp_hyst',
        'pwm3_auto_point${i}_temp',
        'pwm1_auto_point${i}_accel',
        'pwm1_auto_point${i}_decel',
      ]) {
        await File('${controller.path}/$field').writeAsString('0');
      }
    }
    expect(
      await LegionSysfsService(
        hwmonRoot: hwmonRoot.path,
        fanHwmonRoot: controllerRoot.path,
      ).readFanCurve(),
      isNull,
    );
  });

  test(
    'reads a variable-size speed-only level table without temperatures',
    () async {
      final platform = Directory('${root.path}/platform/legion')
        ..createSync(recursive: true);
      final controller = Directory('${controllerRoot.path}/hwmon0')
        ..createSync();
      File('${platform.path}/fancurve_speed_unit').writeAsStringSync('level\n');
      File('${platform.path}/fan1_level_rpm_table')
          .writeAsStringSync('0 1000 2000 3000\n');
      File('${platform.path}/fan2_level_rpm_table')
          .writeAsStringSync('900 1900 2900 3900\n');
      File('${controller.path}/auto_points_size').writeAsStringSync('4\n');
      for (var i = 1; i <= 4; i++) {
        final pwm = [25, 51, 76, 255][i - 1];
        File('${controller.path}/pwm1_auto_point${i}_pwm')
            .writeAsStringSync('$pwm\n');
      }
      final curve = await LegionSysfsService(
        hwmonRoot: hwmonRoot.path,
        fanHwmonRoot: controllerRoot.path,
        legionPlatformRoots: [platform.path],
      ).readFanCurve();
      expect(curve, isNotNull);
      expect(curve!.schema, FanCurveSchema.speedOnly);
      expect(curve.points, hasLength(4));
      expect(curve.points.map((point) => point.fan1Level), [1, 2, 3, 10]);
      expect(curve.points.map((point) => point.fan1Rpm), [0, 1000, 2000, null]);
      expect(curve.points.map((point) => point.fan2Rpm), [
        900,
        1900,
        2900,
        null,
      ]);
      expect(curve.canEdit, isFalse);
    },
  );

  test('does not invent RPMs when a level ladder is missing', () async {
    final platform = Directory('${root.path}/platform/legion')
      ..createSync(recursive: true);
    final controller = Directory('${controllerRoot.path}/hwmon0')..createSync();
    File('${platform.path}/fancurve_speed_unit').writeAsStringSync('level');
    File('${controller.path}/auto_points_size').writeAsStringSync('1');
    File('${controller.path}/pwm1_auto_point1_pwm').writeAsStringSync('25');
    final curve = await LegionSysfsService(
      hwmonRoot: hwmonRoot.path,
      fanHwmonRoot: controllerRoot.path,
      legionPlatformRoots: [platform.path],
    ).readFanCurve();
    expect(curve, isNotNull);
    expect(curve!.fan1LevelRpmTable, isNull);
    expect(curve.points.single.fan1Level, 1);
    expect(curve.points.single.fan1Rpm, isNull);
  });

  test(
    'rejects malformed ladders and point counts without losing table units',
    () async {
      final platform = Directory('${root.path}/platform/legion')
        ..createSync(recursive: true);
      final controller = Directory('${controllerRoot.path}/hwmon0')
        ..createSync();
      final size = File('${controller.path}/auto_points_size')
        ..writeAsStringSync('1');
      final unit = File('${platform.path}/fancurve_speed_unit')
        ..writeAsStringSync('level');
      final ladder = File('${platform.path}/fan1_level_rpm_table');
      File('${controller.path}/pwm1_auto_point1_pwm').writeAsStringSync('51');
      final service = LegionSysfsService(
        hwmonRoot: hwmonRoot.path,
        fanHwmonRoot: controllerRoot.path,
        legionPlatformRoots: [platform.path],
      );
      for (final raw in [
        '1000 invalid',
        '2000 1000',
        '1:1000 2:2000',
        '0 0',
        '1 2 3 4 5 6 7 8 9 10 11',
      ]) {
        ladder.writeAsStringSync(raw);
        final curve = await service.readFanCurve();
        expect(curve, isNotNull);
        expect(curve!.points.single.fan1Level, 2);
        expect(curve.points.single.fan1Rpm, isNull, reason: raw);
      }
      for (final raw in ['0', '11', 'unknown']) {
        size.writeAsStringSync(raw);
        expect(await service.readFanCurve(), isNull, reason: raw);
      }
      size.writeAsStringSync('1');
      unit.writeAsStringSync('percent');
      final percent = (await service.readFanCurve())!;
      expect(percent.speedUnit, FanSpeedUnit.percent);
      expect(percent.points.single.fan1Pwm, 51);
      expect(percent.points.single.fan1Level, isNull);
      expect(percent.points.single.fan1Rpm, isNull);
      expect(percent.canEdit, isFalse);
    },
  );

  test('discovers the Kernel 7 synthetic platform root', () async {
    final virtualRoot = Directory('${root.path}/platform/legion');
    final legacyRoot = Directory('${root.path}/platform/PNP0C09:00');
    final controller = Directory('${virtualRoot.path}/hwmon/hwmon0');
    await controller.create(recursive: true);
    await File('${controller.path}/fan1_input').writeAsString('3600\n');

    final service = LegionSysfsService(
      hwmonRoot: hwmonRoot.path,
      legionPlatformRoots: [virtualRoot.path, legacyRoot.path],
    );

    expect(await service.readFan1Rpm(), 3600);
  });

  test('falls back to the legacy platform root for feature reads', () async {
    final virtualRoot = Directory('${root.path}/platform/legion');
    final legacyRoot = Directory('${root.path}/platform/PNP0C09:00');
    await legacyRoot.create(recursive: true);
    await File('${legacyRoot.path}/gsync').writeAsString('1\n');
    await File('${legacyRoot.path}/cpu_longterm_powerlimit')
        .writeAsString('54\n');

    final service = LegionSysfsService(
      hwmonRoot: hwmonRoot.path,
      legionPlatformRoots: [virtualRoot.path, legacyRoot.path],
    );

    expect(await service.readHybridMode(), isTrue);
    expect(await service.readLegionIntFile('cpu_longterm_powerlimit'), 54);
  });
}
