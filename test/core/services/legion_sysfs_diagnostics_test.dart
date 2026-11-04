import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/models/hardware_check.dart';
import 'package:legion_frontend/core/models/sysfs_probe.dart';
import 'package:legion_frontend/core/services/legion_sysfs_service.dart';

void main() {
  late Directory root;
  late LegionSysfsService service;

  void write(String path, String value) {
    final file = File('${root.path}/$path');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('$value\n');
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('legion-diagnostics-');
    service = LegionSysfsService(
      sysRoot: '${root.path}/sys',
      procRoot: '${root.path}/proc',
    );
  });
  tearDown(() => root.delete(recursive: true));

  test(
    'alternate synthetic layout reports the actual reader selections',
    () async {
      final fixture =
          jsonDecode(
                File(
                  'test/fixtures/sysfs/alternate-layout.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      fixture.forEach((path, value) => write(path, value as String));
      write('sys/class/dmi/id/product_serial', 'DO-NOT-EXPORT-SERIAL');
      write('sys/class/dmi/id/product_uuid', 'DO-NOT-EXPORT-UUID');
      write('sys/class/hwmon/hwmon0/name', 'unidentified-fan');
      write('sys/class/hwmon/hwmon0/fan1_input', '9999');

      final results = await service.readHardwareProbes();
      final probes = results.checks;
      expect(
        probes[HardwareCheck.biosVersion]?.selectedRead?.value,
        'FIXTURE-BIOS',
      );
      expect(
        probes[HardwareCheck.batteryConservation]?.selectedRead?.path,
        '/sys/bus/platform/drivers/ideapad_acpi/VPC2004:01/conservation_mode',
      );
      expect(probes[HardwareCheck.keyboardBacklight]?.selectedRead?.value, '2');
      expect(
        probes[HardwareCheck.fan1Rpm]?.selectedRead?.path,
        '/sys/class/hwmon/hwmon7/fan1_input',
      );
      expect(
        probes[HardwareCheck.fan1Rpm]?.selectedRead?.value,
        '${await service.readFan1Rpm()}',
      );
      expect(probes[HardwareCheck.fan2Rpm]?.selectedRead?.value, '0');
      expect(
        probes[HardwareCheck.acOnline]?.selectedRead?.path,
        '/sys/class/power_supply/USBC/online',
      );
      expect(await service.readBatteryConservationMode(), isTrue);
      expect(await service.readWhiteKeyboardBacklightMode(), isTrue);
      final exported = jsonEncode(
        [
          ...probes.values,
          ...results.sensorProviders,
        ].map((probe) => probe.toJson()).toList(),
      );
      expect(exported, isNot(contains('DO-NOT-EXPORT')));
      expect(exported, isNot(contains(root.path)));
      expect(exported, isNot(contains('9999')));
      expect(exported, contains('unidentified-fan'));
    },
  );

  test('missing, malformed, unreadable and unknown remain distinct', () async {
    write('sys/firmware/acpi/platform_profile', '');
    write(
      'sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/conservation_mode',
      'garbage',
    );
    // A directory cannot be read as a file, even when the test runs as root.
    Directory(
      '${root.path}/sys/class/dmi/id/bios_version',
    ).createSync(recursive: true);
    // ELOOP is an unexpected filesystem failure, not an absent capability.
    final loop = '${root.path}/sys/class/dmi/id/product_name';
    Link(loop).createSync(loop);
    final probes = (await service.readHardwareProbes()).checks;
    expect(probes.keys, unorderedEquals(HardwareCheck.values));
    expect(
      probes[HardwareCheck.productFamily]?.outcome,
      SysfsReadOutcome.missing,
    );
    expect(
      probes[HardwareCheck.biosVersion]?.outcome,
      SysfsReadOutcome.unreadable,
    );
    expect(
      probes[HardwareCheck.productName]?.outcome,
      SysfsReadOutcome.unknown,
    );
    expect(
      probes[HardwareCheck.platformProfile]?.outcome,
      SysfsReadOutcome.malformed,
    );
    expect(
      probes[HardwareCheck.batteryConservation]?.outcome,
      SysfsReadOutcome.malformed,
    );
    expect(probes[HardwareCheck.batteryConservation]?.selectedRead, isNull);
    expect(
      jsonEncode(probes[HardwareCheck.batteryConservation]?.toJson()),
      isNot(contains('garbage')),
    );
  });

  test(
    'malformed boolean keeps legacy failure; integer readers can fall back',
    () async {
      const driver = 'sys/bus/platform/drivers/ideapad_acpi';
      write('$driver/VPC2004:00/conservation_mode', 'broken');
      write('$driver/VPC2004:01/conservation_mode', '1');
      write('sys/class/leds/platform::kbd_backlight/brightness', 'broken');
      write('sys/class/leds/ideapad::kbd_backlight/brightness', '1');
      final probes = (await service.readHardwareProbes()).checks;
      expect(
        probes[HardwareCheck.batteryConservation]?.outcome,
        SysfsReadOutcome.malformed,
      );
      await expectLater(
        service.readBatteryConservationMode(),
        throwsFormatException,
      );
      expect(
        probes[HardwareCheck.keyboardBacklight]?.outcome,
        SysfsReadOutcome.readable,
      );
      expect(
        probes[HardwareCheck.keyboardBacklight]?.reads.first.outcome,
        SysfsReadOutcome.malformed,
      );
      expect(await service.readWhiteKeyboardBacklightMode(), isTrue);
    },
  );

  test('invalid provider names cannot abort the remaining report', () async {
    write('sys/class/hwmon/hwmon0/name', 'placeholder');
    File('${root.path}/sys/class/hwmon/hwmon0/name').writeAsBytesSync([0xff]);
    write('sys/class/hwmon/hwmon1/name', 'yogafan');
    write('sys/class/hwmon/hwmon1/fan1_input', '2500');
    final results = await service.readHardwareProbes();
    expect(results.sensorProviders.first.outcome, SysfsReadOutcome.malformed);
    expect(results.checks[HardwareCheck.fan1Rpm]?.selectedRead?.value, '2500');
    expect(await service.readFan1Rpm(), 2500);
  });

  test('fan provider follows the successful fallback input', () async {
    const controller =
        'sys/module/legion_laptop/drivers/platform:legion/legion/hwmon/hwmon0';
    write('$controller/name', 'legion_hwmon');
    write('$controller/fan1_input', 'invalid');
    write('sys/class/hwmon/hwmon7/name', 'yogafan');
    write('sys/class/hwmon/hwmon7/fan1_input', '3200');
    final probes = (await service.readHardwareProbes()).checks;
    expect(
      probes[HardwareCheck.fan1Rpm]?.reads.first.outcome,
      SysfsReadOutcome.malformed,
    );
    expect(probes[HardwareCheck.fan1Rpm]?.selectedRead?.value, '3200');
    expect(probes[HardwareCheck.fan1Provider]?.selectedRead?.value, 'yogafan');
    expect(
      probes[HardwareCheck.fan1Provider]?.selectedRead?.path,
      '/sys/class/hwmon/hwmon7/name',
    );
  });

  test(
    'empty boolean falls through and alternate Legion roots remain selected',
    () async {
      const ideapad = 'sys/bus/platform/drivers/ideapad_acpi';
      const legion = 'sys/module/legion_laptop/drivers/platform:legion';
      write('$ideapad/VPC2004:00/conservation_mode', '');
      write('$ideapad/VPC2004:01/conservation_mode', '1');
      write('$legion/PNP0C09:00/gsync', '0');
      write('$legion/PNP0C09:00/hwmon/hwmon8/name', 'legion_hwmon');
      write('$legion/PNP0C09:00/hwmon/hwmon8/fan1_input', '4100');
      final probes = (await service.readHardwareProbes()).checks;
      expect(
        probes[HardwareCheck.batteryConservation]?.outcome,
        SysfsReadOutcome.readable,
      );
      expect(
        probes[HardwareCheck.batteryConservation]?.reads.first.outcome,
        SysfsReadOutcome.malformed,
      );
      expect(await service.readBatteryConservationMode(), isTrue);
      expect(
        probes[HardwareCheck.hybridMode]?.selectedRead?.path,
        '/$legion/PNP0C09:00/gsync',
      );
      expect(
        probes[HardwareCheck.fan1Rpm]?.selectedRead?.value,
        '${await service.readFan1Rpm()}',
      );
      expect(
        probes[HardwareCheck.fan1Provider]?.selectedRead?.value,
        'legion_hwmon',
      );
    },
  );
}
