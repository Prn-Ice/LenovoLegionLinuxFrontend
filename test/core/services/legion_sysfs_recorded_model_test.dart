import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/models/hardware_check.dart';
import 'package:legion_frontend/core/models/sysfs_probe.dart';
import 'package:legion_frontend/core/services/legion_sysfs_service.dart';
import 'package:legion_frontend/features/fans/models/fan_curve.dart';

Future<LegionSysfsService> _replayFixture(String fixturePath) async {
  final root = await Directory.systemTemp.createTemp('legion-recorded-model-');
  addTearDown(() => root.delete(recursive: true));
  final files =
      jsonDecode(await File(fixturePath).readAsString()) as Map<String, dynamic>;
  for (final entry in files.entries) {
    final file = File('${root.path}/${entry.key}');
    await file.parent.create(recursive: true);
    await file.writeAsString('${entry.value}\n');
  }
  return LegionSysfsService(
    sysRoot: '${root.path}/sys',
    procRoot: '${root.path}/proc',
  );
}

void main() {
  test('replays the recorded 82Y4 power, fan and adapter paths', () async {
    final sysfs = await _replayFixture(
      'test/fixtures/sysfs/82y4-m1cn48ww-readonly.json',
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

  test(
    'replays the recorded Kernel 7.3.4 82Y4 level fan curve and probes',
    () async {
      final sysfs = await _replayFixture(
        'test/fixtures/sysfs/82y4-m1cn48ww-kernel734-readonly.json',
      );

      final curve = await sysfs.readFanCurve();
      expect(curve, isNotNull);
      expect(curve!.schema, FanCurveSchema.speedOnly);
      expect(curve.speedUnit, FanSpeedUnit.level);
      expect(curve.writeStatus, FanCurveWriteStatus.unsupported);
      expect(curve.canEdit, isFalse);
      expect(curve.activePointCount, 10);
      expect(curve.fan1LevelRpmTable, const [
        0,
        1800,
        1900,
        2100,
        2400,
        2800,
        2900,
        3600,
        4100,
        4700,
      ]);
      expect(curve.fan2LevelRpmTable, const [
        0,
        1800,
        1900,
        2100,
        2400,
        2800,
        2900,
        3600,
        4100,
        4700,
      ]);
      expect(
        curve.points.map((point) => point.fan1Level).toList(),
        const [1, 2, 3, 4, 5, 6, 7, 8, 8, 8],
      );
      expect(
        curve.points.map((point) => point.fan1Pwm).toList(),
        const [25, 51, 76, 102, 127, 153, 178, 204, 204, 204],
      );
      expect(
        curve.points.map((point) => point.fan1Rpm).toList(),
        const [0, 1800, 1900, 2100, 2400, 2800, 2900, 3600, 3600, 3600],
      );
      expect(
        curve.points.map((point) => point.fan2Rpm).toList(),
        const [0, 1800, 1900, 2100, 2400, 2800, 2900, 3600, 3600, 3600],
      );

      expect(await sysfs.readMiniFanCurveMode(), isNull);
      expect(await sysfs.readLockFanControllerMode(), isNull);
      expect(await sysfs.readMaximumFanSpeedMode(), isFalse);
      expect(await sysfs.readFan1Rpm(), 0);
      expect(await sysfs.readFan2Rpm(), 0);
      expect(await sysfs.readFan3Rpm(), isNull);
      expect(await sysfs.readFan1MaxRpm(), 10000);
      expect(await sysfs.readRapidChargingMode(), isFalse);
      expect(await sysfs.readLegionIntFile('gpu_ppab_powerlimit'), 20);

      final results = await sysfs.readHardwareProbes();
      expect(
        results.checks[HardwareCheck.kernelVersion]?.selectedRead?.value,
        '7.3.4',
      );
      expect(
        results.checks[HardwareCheck.fan1Provider]?.selectedRead?.value,
        'legion_hwmon',
      );
      expect(
        results.checks[HardwareCheck.miniFanCurve]?.outcome,
        SysfsReadOutcome.missing,
      );
      expect(
        results.checks[HardwareCheck.lockFanController]?.outcome,
        SysfsReadOutcome.missing,
      );
      expect(
        results.checks[HardwareCheck.fanFullspeed]?.selectedRead?.value,
        '0',
      );
      expect(
        results.checks[HardwareCheck.rapidCharge]?.selectedRead?.value,
        '0',
      );
      expect(results.checks[HardwareCheck.gpuPpab]?.selectedRead?.value, '20');
    },
  );
}
