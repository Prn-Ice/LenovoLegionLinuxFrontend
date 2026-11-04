import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/models/hardware_check.dart';
import 'package:legion_frontend/core/services/legion_sysfs_service.dart';

void main() {
  test('replays the recorded 82Y4 power, fan and adapter paths', () async {
    final root = await Directory.systemTemp.createTemp(
      'legion-recorded-model-',
    );
    addTearDown(() => root.delete(recursive: true));
    final files =
        jsonDecode(
              await File(
                'test/fixtures/sysfs/82y4-m1cn48ww-readonly.json',
              ).readAsString(),
            )
            as Map<String, dynamic>;
    for (final entry in files.entries) {
      final file = File('${root.path}/${entry.key}');
      await file.parent.create(recursive: true);
      await file.writeAsString('${entry.value}\n');
    }
    final sysfs = LegionSysfsService(
      sysRoot: '${root.path}/sys',
      procRoot: '${root.path}/proc',
    );

    expect(await sysfs.readFan1Rpm(), 1800);
    expect(await sysfs.readFan2Rpm(), 1500);
    expect(await sysfs.readOnPowerSupplyMode(), isFalse);
    expect(await sysfs.readBatteryConservationMode(), isFalse);
    expect(await sysfs.readLegionIntFile('cpu_longterm_powerlimit'), 54);

    final results = await sysfs.readHardwareProbes();
    expect(
      results.checks[HardwareCheck.fan1Provider]?.selectedRead?.value,
      'legion_hwmon',
    );
    expect(
      results.checks[HardwareCheck.fan1Rpm]?.selectedRead?.path,
      '/sys/module/legion_laptop/drivers/platform:legion/legion/hwmon/hwmon2/fan1_input',
    );
    expect(
      results.checks[HardwareCheck.acOnline]?.selectedRead?.path,
      '/sys/class/power_supply/ACAD/online',
    );
  });
}
