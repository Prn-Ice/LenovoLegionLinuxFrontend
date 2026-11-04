import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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

      final probes = await service.readHardwareProbes();
      expect(probes['bios_version']?.selectedRead?.value, 'FIXTURE-BIOS');
      expect(
        probes['battery_conservation']?.selectedRead?.path,
        '/sys/bus/platform/drivers/ideapad_acpi/VPC2004:01/conservation_mode',
      );
      expect(probes['keyboard_backlight']?.selectedRead?.value, '2');
      expect(
        probes['fan1_rpm']?.selectedRead?.path,
        '/sys/class/hwmon/hwmon7/fan1_input',
      );
      expect(
        probes['fan1_rpm']?.selectedRead?.value,
        '${await service.readFan1Rpm()}',
      );
      expect(probes['fan2_rpm']?.selectedRead?.value, '0');
      expect(
        probes['ac_online']?.selectedRead?.path,
        '/sys/class/power_supply/USBC/online',
      );
      expect(await service.readBatteryConservationMode(), isTrue);
      expect(await service.readWhiteKeyboardBacklightMode(), isTrue);
      final exported = jsonEncode(
        probes.map((id, probe) => MapEntry(id, probe.toJson())),
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
    final probes = await service.readHardwareProbes();
    expect(probes['product_family']?.outcome, SysfsReadOutcome.missing);
    expect(probes['bios_version']?.outcome, SysfsReadOutcome.unreadable);
    expect(probes['product_name']?.outcome, SysfsReadOutcome.unknown);
    expect(probes['platform_profile']?.outcome, SysfsReadOutcome.malformed);
    expect(probes['battery_conservation']?.outcome, SysfsReadOutcome.malformed);
    expect(probes['battery_conservation']?.selectedRead, isNull);
    expect(
      jsonEncode(probes['battery_conservation']?.toJson()),
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
      final probes = await service.readHardwareProbes();
      expect(
        probes['battery_conservation']?.outcome,
        SysfsReadOutcome.malformed,
      );
      await expectLater(
        service.readBatteryConservationMode(),
        throwsFormatException,
      );
      expect(probes['keyboard_backlight']?.outcome, SysfsReadOutcome.readable);
      expect(
        probes['keyboard_backlight']?.reads.first.outcome,
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
    final probes = await service.readHardwareProbes();
    expect(probes['hwmon_provider_1']?.outcome, SysfsReadOutcome.malformed);
    expect(probes['fan1_rpm']?.selectedRead?.value, '2500');
    expect(await service.readFan1Rpm(), 2500);
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
      final probes = await service.readHardwareProbes();
      expect(
        probes['battery_conservation']?.outcome,
        SysfsReadOutcome.readable,
      );
      expect(
        probes['battery_conservation']?.reads.first.outcome,
        SysfsReadOutcome.malformed,
      );
      expect(await service.readBatteryConservationMode(), isTrue);
      expect(
        probes['hybrid_mode']?.selectedRead?.path,
        '/$legion/PNP0C09:00/gsync',
      );
      expect(
        probes['fan1_rpm']?.selectedRead?.value,
        '${await service.readFan1Rpm()}',
      );
      expect(probes['fan1_provider']?.selectedRead?.value, 'legion_hwmon');
    },
  );
}
