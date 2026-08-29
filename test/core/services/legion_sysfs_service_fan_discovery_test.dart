import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/services/legion_sysfs_service.dart';

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
}
