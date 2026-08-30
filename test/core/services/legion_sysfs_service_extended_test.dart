import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/services/legion_sysfs_service.dart';

void main() {
  // These are integration-style tests that return null on CI (no hardware).
  // They verify the methods exist and return null gracefully, not actual values.
  final service = LegionSysfsService();

  group('LegionSysfsService extended reads', () {
    test(
      'readCpuPolicySnapshot reads effective policy with global boost',
      () async {
        final root = await Directory.systemTemp.createTemp('cpu-policy-test-');
        addTearDown(() => root.delete(recursive: true));
        final policy = Directory('${root.path}/cpufreq/policy0')
          ..createSync(recursive: true);
        final pstate = Directory('${root.path}/amd_pstate')
          ..createSync(recursive: true);

        File(
          '${policy.path}/scaling_driver',
        ).writeAsStringSync('amd-pstate-epp');
        File('${policy.path}/scaling_governor').writeAsStringSync('powersave');
        File(
          '${policy.path}/energy_performance_preference',
        ).writeAsStringSync('balance_performance');
        File('${policy.path}/scaling_min_freq').writeAsStringSync('420000');
        File('${policy.path}/scaling_max_freq').writeAsStringSync('3800000');
        File('${pstate.path}/status').writeAsStringSync('active');
        File('${root.path}/cpufreq/boost').writeAsStringSync('1');

        final snapshot = await LegionSysfsService(
          cpuPolicyRoot: policy.path,
          amdPstateRoot: pstate.path,
          cpuFreqRoot: '${root.path}/cpufreq',
        ).readCpuPolicySnapshot();

        expect(snapshot?.driver, 'amd-pstate-epp');
        expect(snapshot?.pstateStatus, 'active');
        expect(snapshot?.governor, 'powersave');
        expect(snapshot?.energyPerformancePreference, 'balance_performance');
        expect(snapshot?.boostEnabled, isTrue);
        expect(snapshot?.minimumFrequencyKhz, 420000);
        expect(snapshot?.maximumFrequencyKhz, 3800000);
      },
    );

    test('readCpuPolicySnapshot ignores an unexpected boost value', () async {
      final root = await Directory.systemTemp.createTemp('cpu-policy-test-');
      addTearDown(() => root.delete(recursive: true));
      final policy = Directory('${root.path}/cpufreq/policy0')
        ..createSync(recursive: true);
      File('${policy.path}/scaling_governor').writeAsStringSync('powersave');
      File('${root.path}/cpufreq/boost').writeAsStringSync('unexpected');

      final snapshot = await LegionSysfsService(
        cpuPolicyRoot: policy.path,
        amdPstateRoot: '${root.path}/amd_pstate',
        cpuFreqRoot: '${root.path}/cpufreq',
      ).readCpuPolicySnapshot();

      expect(snapshot?.governor, 'powersave');
      expect(snapshot?.boostEnabled, isNull);
    });

    test(
      'readCpuUtilisationPercent returns double? without throwing',
      () async {
        final result = await service.readCpuUtilisationPercent();
        expect(result, anyOf(isNull, isA<double>()));
      },
    );

    test('readAverageCpuClockGhz returns double? without throwing', () async {
      final result = await service.readAverageCpuClockGhz();
      expect(result, anyOf(isNull, isA<double>()));
    });

    test('readBatteryCycleCount returns int? without throwing', () async {
      final result = await service.readBatteryCycleCount();
      expect(result, anyOf(isNull, isA<int>()));
    });

    test(
      'readBatteryFullCapacityWh returns double? without throwing',
      () async {
        final result = await service.readBatteryFullCapacityWh();
        expect(result, anyOf(isNull, isA<double>()));
      },
    );

    test(
      'readBatteryDesignCapacityWh returns double? without throwing',
      () async {
        final result = await service.readBatteryDesignCapacityWh();
        expect(result, anyOf(isNull, isA<double>()));
      },
    );

    test(
      'readBatteryCurrentCapacityWh returns double? without throwing',
      () async {
        final result = await service.readBatteryCurrentCapacityWh();
        expect(result, anyOf(isNull, isA<double>()));
      },
    );

    test('readBatteryPowerDrawW returns double? without throwing', () async {
      final result = await service.readBatteryPowerDrawW();
      expect(result, anyOf(isNull, isA<double>()));
    });

    test('readBatteryTempC returns double? without throwing', () async {
      final result = await service.readBatteryTempC();
      expect(result, anyOf(isNull, isA<double>()));
    });

    test('readMotherboardTempC returns double? without throwing', () async {
      final result = await service.readMotherboardTempC();
      expect(result, anyOf(isNull, isA<double>()));
    });

    test(
      'keeps ACPI system temperature separate from CPU temperature',
      () async {
        final root = await Directory.systemTemp.createTemp('hwmon-temp-test-');
        addTearDown(() => root.delete(recursive: true));
        final acpi = Directory('${root.path}/hwmon0')..createSync();
        File('${acpi.path}/name').writeAsStringSync('acpitz\n');
        File('${acpi.path}/temp1_input').writeAsStringSync('42000\n');

        final temperatureService = LegionSysfsService(hwmonRoot: root.path);

        expect(await temperatureService.readCpuTempC(), isNull);
        expect(await temperatureService.readMotherboardTempC(), 42);
      },
    );

    test('prefers the labeled Legion CPU temperature', () async {
      final root = await Directory.systemTemp.createTemp('hwmon-temp-test-');
      addTearDown(() => root.delete(recursive: true));
      final legion = Directory('${root.path}/hwmon0')..createSync();
      File('${legion.path}/name').writeAsStringSync('legion_hwmon\n');
      File('${legion.path}/temp2_label').writeAsStringSync('CPU Temperature\n');
      File('${legion.path}/temp2_input').writeAsStringSync('61000\n');
      final acpi = Directory('${root.path}/hwmon1')..createSync();
      File('${acpi.path}/name').writeAsStringSync('acpitz\n');
      File('${acpi.path}/temp1_input').writeAsStringSync('42000\n');

      final temperatureService = LegionSysfsService(hwmonRoot: root.path);

      expect(await temperatureService.readCpuTempC(), 61);
      expect(await temperatureService.readMotherboardTempC(), 42);
    });

    test('readDiskTempC returns double? without throwing', () async {
      final result = await service.readDiskTempC();
      expect(result, anyOf(isNull, isA<double>()));
    });

    test('readDeviceProductFamily returns String? without throwing', () async {
      final result = await service.readDeviceProductFamily();
      expect(result, anyOf(isNull, isA<String>()));
    });

    test('readDeviceProductName returns String? without throwing', () async {
      final result = await service.readDeviceProductName();
      expect(result, anyOf(isNull, isA<String>()));
    });

    test('readDeviceSerial returns String? without throwing', () async {
      final result = await service.readDeviceSerial();
      expect(result, anyOf(isNull, isA<String>()));
    });

    test('readBiosVersion returns String? without throwing', () async {
      final result = await service.readBiosVersion();
      expect(result, anyOf(isNull, isA<String>()));
    });

    test('readCpuName returns String? without throwing', () async {
      final result = await service.readCpuName();
      expect(result, anyOf(isNull, isA<String>()));
    });
  });
}
