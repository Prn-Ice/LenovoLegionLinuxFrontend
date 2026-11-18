import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/services/igpu_sysfs_service.dart';

void main() {
  late Directory root;
  late IgpuSysfsService service;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('igpu-sysfs-');
    service = IgpuSysfsService(drmPath: root.path);
    addTearDown(() => root.delete(recursive: true));
  });

  Future<void> write(String path, String value) async {
    final file = File('${root.path}/$path');
    await file.parent.create(recursive: true);
    await file.writeAsString(value);
  }

  Future<void> gpu(String card, {int format = 2, String usage = '23'}) async {
    await write('$card/device/vendor', '0x1002');
    await write('$card/device/uevent', 'DRIVER=amdgpu\n');
    await write('$card/device/power/runtime_status', 'active');
    // A synthetic header from the kernel's APU metrics layout.
    await File('${root.path}/$card/device/gpu_metrics')
        .writeAsBytes([4, 0, format, 1]);
    await write('$card/device/gpu_busy_percent', usage);
    await write('$card/device/hwmon/hwmon7/name', 'amdgpu');
    await write('$card/device/hwmon/hwmon7/temp1_input', '48500');
  }

  test(
    'reads the APU regardless of card order and ignores discrete metrics',
    () async {
      await gpu('card0', format: 1, usage: '91');
      await gpu('card3');
      await gpu('card3-eDP-1', usage: '99');
      final reading = await service.readSnapshot();
      expect(reading?.usagePercent, 23);
      expect(reading?.tempC, 48.5);
    },
  );

  test(
    'keeps real zero and rejects missing, invalid, and out-of-range usage',
    () async {
      await gpu('card1', format: 3, usage: '0');
      expect((await service.readSnapshot())?.usagePercent, 0);
      for (final value in ['-1', '101', 'NaN', 'Infinity', 'unavailable']) {
        await write('card1/device/gpu_busy_percent', value);
        final reading = await service.readSnapshot();
        expect(reading?.usagePercent, isNull);
        expect(reading?.tempC, 48.5);
      }
      await File('${root.path}/card1/device/gpu_busy_percent').delete();
      expect((await service.readSnapshot())?.usagePercent, isNull);
    },
  );

  test('hides suspended, unidentified, and ambiguous devices', () async {
    await gpu('card1');
    await write('card1/device/power/runtime_status', 'suspended');
    expect(await service.readSnapshot(), isNull);
    await write('card1/device/power/runtime_status', 'active');
    await File('${root.path}/card1/device/gpu_metrics')
        .writeAsBytes([4, 0, 9, 0]);
    expect(await service.readSnapshot(), isNull);
    await gpu('card1');
    await gpu('card2');
    expect(await service.readSnapshot(), isNull);
  });

  test(
    'handles absent DRM and truncated metrics without substituting another GPU',
    () async {
      expect(await service.readSnapshot(), isNull);
      await gpu('card1');
      await File('${root.path}/card1/device/gpu_metrics').writeAsBytes([4, 0]);
      expect(await service.readSnapshot(), isNull);
      await root.delete(recursive: true);
      expect(await service.readSnapshot(), isNull);
      await root.create();
    },
  );
}
