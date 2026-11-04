import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/services/legion_sysfs_service.dart';

void main() {
  late Directory root;
  late LegionSysfsService service;

  void write(String path, Object value) {
    final file = File('${root.path}/$path');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('$value\n');
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('legion-sysfs-');
    service = LegionSysfsService(
      sysRoot: '${root.path}/sys',
      procRoot: '${root.path}/proc',
    );
  });
  tearDown(() => root.delete(recursive: true));

  test(
    'empty roots report unavailable hardware without host fallback',
    () async {
      final reads = <Future<Object?>>[
        service.readCpuPolicySnapshot(),
        service.readCpuUtilisationPercent(),
        service.readAverageCpuClockGhz(),
        service.readCpuName(),
        service.readKernelRelease(),
        service.readUptimeSeconds(),
        service.readLegionModuleVersion(),
        service.readPlatformProfile(),
        service.readBatteryPercent(),
        service.readBatteryCycleCount(),
        service.readBatteryFullCapacityWh(),
        service.readBatteryDesignCapacityWh(),
        service.readBatteryCurrentCapacityWh(),
        service.readBatteryPowerDrawW(),
        service.readBatteryTempC(),
        service.readBatteryVoltageV(),
        service.readBatteryManufacturer(),
        service.readBatteryModelName(),
        service.readBatterySerialNumber(),
        service.readBatteryStatus(),
        service.readDeviceProductFamily(),
        service.readDeviceProductName(),
        service.readDeviceSerial(),
        service.readBiosVersion(),
        service.readCpuTempC(),
        service.readGpuTempC(),
        service.readMotherboardTempC(),
        service.readDiskTempC(),
        service.readFan1Rpm(),
        service.readFan2Rpm(),
        service.readFanCurve(),
        service.readHybridMode(),
        service.readBatteryConservationMode(),
        service.readWhiteKeyboardBacklightMode(),
        service.readOnPowerSupplyMode(),
      ];
      expect(await Future.wait(reads), everyElement(isNull));
      expect(await service.readPlatformProfileChoices(), isEmpty);
      expect((await service.readSystemStatus()).error, isNotNull);
    },
  );

  test(
    'sys and proc roots supply identity, profile and clock values',
    () async {
      for (final entry in {
        'product_family': 'Legion fixture',
        'product_name': 'Test model',
        'product_serial': 'fixture-123',
        'bios_version': 'TEST42',
      }.entries) {
        write('sys/class/dmi/id/${entry.key}', entry.value);
      }
      write('proc/cpuinfo', 'processor : 0\nmodel name : Fixture CPU: 8 cores');
      write('proc/sys/kernel/osrelease', '7.0-fixture');
      write('proc/uptime', '123.6 99.0');
      write('sys/module/legion_laptop/version', 'fixture-version');
      write('sys/firmware/acpi/platform_profile', 'balanced');
      write(
        'sys/firmware/acpi/platform_profile_choices',
        'quiet [balanced] performance balanced',
      );
      write('sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq', 2000000);
      write('sys/devices/system/cpu/cpu1/cpufreq/scaling_cur_freq', 3000000);
      write('sys/devices/system/cpu/cpu2/cpufreq/scaling_cur_freq', 0);
      write('sys/devices/system/cpu/cpu3/cpufreq/scaling_cur_freq', 'invalid');
      write('sys/devices/system/cpu/notcpu/cpufreq/scaling_cur_freq', 9000000);
      expect(await service.readDeviceProductFamily(), 'Legion fixture');
      expect(await service.readDeviceProductName(), 'Test model');
      expect(await service.readDeviceSerial(), 'fixture-123');
      expect(await service.readBiosVersion(), 'TEST42');
      expect(await service.readCpuName(), 'Fixture CPU: 8 cores');
      expect(await service.readKernelRelease(), '7.0-fixture');
      expect(await service.readUptimeSeconds(), 124);
      expect(await service.readLegionModuleVersion(), 'fixture-version');
      expect(await service.readPlatformProfileChoices(), [
        'quiet',
        'balanced',
        'performance',
      ]);
      expect((await service.readSystemStatus()).powerProfile, 'balanced');
      expect((await service.readSystemStatus()).error, isNull);
      expect(await service.readAverageCpuClockGhz(), 2.5);
    },
  );

  test(
    'CPU policy uses injected defaults and policy boost before global',
    () async {
      const policy = 'sys/devices/system/cpu/cpufreq/policy0';
      for (final entry in {
        'scaling_driver': 'amd-pstate-epp',
        'scaling_governor': 'powersave',
        'energy_performance_preference': 'balance_performance',
        'scaling_min_freq': '420000',
        'scaling_max_freq': '3800000',
      }.entries) {
        write('$policy/${entry.key}', entry.value);
      }
      write('sys/devices/system/cpu/amd_pstate/status', 'active');
      write('sys/devices/system/cpu/cpufreq/boost', 1);
      final snapshot = await service.readCpuPolicySnapshot();
      expect(snapshot?.driver, 'amd-pstate-epp');
      expect(snapshot?.pstateStatus, 'active');
      expect(snapshot?.governor, 'powersave');
      expect(snapshot?.energyPerformancePreference, 'balance_performance');
      expect(snapshot?.minimumFrequencyKhz, 420000);
      expect(snapshot?.maximumFrequencyKhz, 3800000);
      expect(snapshot?.boostEnabled, isTrue);
      write('$policy/boost', 0);
      expect((await service.readCpuPolicySnapshot())?.boostEnabled, isFalse);
      write('$policy/boost', 'unexpected');
      write('sys/devices/system/cpu/cpufreq/boost', 'unexpected');
      expect((await service.readCpuPolicySnapshot())?.boostEnabled, isNull);
    },
  );

  test('explicit roots override the general sys root', () async {
    write('policy/scaling_governor', 'performance');
    write('pstate/status', 'passive');
    write('frequency/boost', 1);
    write('hwmon/hwmon0/name', 'coretemp');
    write('hwmon/hwmon0/temp1_input', 53000);
    final overridden = LegionSysfsService(
      sysRoot: '${root.path}/missing',
      hwmonRoot: '${root.path}/hwmon',
      cpuPolicyRoot: '${root.path}/policy',
      amdPstateRoot: '${root.path}/pstate',
      cpuFreqRoot: '${root.path}/frequency',
    );
    expect((await overridden.readCpuPolicySnapshot())?.governor, 'performance');
    expect((await overridden.readCpuPolicySnapshot())?.pstateStatus, 'passive');
    expect((await overridden.readCpuPolicySnapshot())?.boostEnabled, isTrue);
    expect(await overridden.readCpuTempC(), 53);
  });

  test(
    'discovers typed battery and mains with converted energy units',
    () async {
      const battery = 'sys/class/power_supply/BAT1';
      for (final entry in {
        'type': 'Battery',
        'capacity': '73',
        'status': 'Charging',
        'cycle_count': '123',
        'energy_full': '70000000',
        'energy_full_design': '80000000',
        'energy_now': '51000000',
        'power_now': '12000000',
        'temp': '325',
        'voltage_now': '15000000',
        'manufacturer': 'Fixture',
        'model_name': 'Battery',
        'serial_number': 'B123',
      }.entries) {
        write('$battery/${entry.key}', entry.value);
      }
      write('sys/class/power_supply/USBC/type', 'Mains');
      write('sys/class/power_supply/USBC/online', 1);
      expect(await service.readOnPowerSupplyMode(), isTrue);
      expect(await service.readBatteryPercent(), 73);
      expect(await service.readBatteryStatus(), 'Charging');
      expect(await service.readBatteryCycleCount(), 123);
      expect(await service.readBatteryFullCapacityWh(), 70);
      expect(await service.readBatteryDesignCapacityWh(), 80);
      expect(await service.readBatteryCurrentCapacityWh(), 51);
      expect(await service.readBatteryPowerDrawW(), -12);
      expect(await service.readBatteryTempC(), 32.5);
      expect(await service.readBatteryVoltageV(), 15);
      expect(await service.readBatteryManufacturer(), 'Fixture');
      expect(await service.readBatteryModelName(), 'Battery');
      expect(await service.readBatterySerialNumber(), 'B123');
    },
  );

  test(
    'legacy battery charge/current fallback and AC paths remain supported',
    () async {
      const battery = 'sys/class/power_supply/BAT0';
      write('$battery/charge_full', 4000000);
      write('$battery/charge_full_design', 5000000);
      write('$battery/charge_now', 2000000);
      write('$battery/current_now', 1000000);
      write('$battery/voltage_now', 15000000);
      write('$battery/status', 'Discharging');
      write('sys/class/power_supply/AC/online', 0);
      expect(await service.readBatteryFullCapacityWh(), 60);
      expect(await service.readBatteryDesignCapacityWh(), 75);
      expect(await service.readBatteryCurrentCapacityWh(), 30);
      expect(await service.readBatteryPowerDrawW(), 15);
      expect(await service.readOnPowerSupplyMode(), isFalse);
      write('sys/class/power_supply/ADP0/online', 1);
      expect(await service.readOnPowerSupplyMode(), isTrue);
    },
  );

  test('temperature drivers stay separate and labeled CPU wins', () async {
    void sensor(int index, String name, int value) {
      write('sys/class/hwmon/hwmon$index/name', name);
      write('sys/class/hwmon/hwmon$index/temp1_input', value);
    }

    sensor(0, 'acpitz', 42000);
    expect(await service.readCpuTempC(), isNull);
    expect(await service.readMotherboardTempC(), 42);
    sensor(1, 'coretemp', 55000);
    expect(await service.readCpuTempC(), 55);
    sensor(2, 'legion_hwmon', 49000);
    write('sys/class/hwmon/hwmon2/temp2_label', 'CPU Temperature');
    write('sys/class/hwmon/hwmon2/temp2_input', 61000);
    sensor(3, 'amdgpu', 62500);
    sensor(4, 'nvme', 38500);
    expect(await service.readCpuTempC(), 61);
    expect(await service.readMotherboardTempC(), 42);
    expect(await service.readGpuTempC(), 62.5);
    expect(await service.readDiskTempC(), 38.5);
  });

  test(
    'proc sampling with unchanged counters is unavailable, not host usage',
    () async {
      write('proc/stat', 'cpu  100 0 50 200 0 0 0 0\ncpu0 100 0 50 200');
      expect(await service.readCpuUtilisationPercent(), isNull);
      write('proc/uptime', 'invalid');
      expect(await service.readUptimeSeconds(), isNull);
    },
  );

  test(
    'alternate ideapad symlinks are sorted, legacy values take precedence',
    () async {
      const driver = 'sys/bus/platform/drivers/ideapad_acpi';
      for (final attribute in [
        'conservation_mode',
        'usb_charging',
        'touchpad',
        'camera_power',
        'fn_lock',
      ]) {
        write('devices/ideapad/$attribute', 1);
      }
      Directory('${root.path}/$driver').createSync(recursive: true);
      Link(
        '${root.path}/$driver/VPC2004:01',
      ).createSync('${root.path}/devices/ideapad');
      write('$driver/VPC2004:02/conservation_mode', 0);
      expect(await service.readBatteryConservationMode(), isTrue);
      expect(await service.readAlwaysOnUsbChargingMode(), isTrue);
      expect(await service.readTouchpadMode(), isTrue);
      expect(await service.readCameraPowerMode(), isTrue);
      expect(await service.readFnLockMode(), isTrue);
      write('$driver/VPC2004:00/conservation_mode', 0);
      expect(await service.readBatteryConservationMode(), isFalse);
      write('$driver/VPC2004:00/fn_lock', 'invalid');
      await expectLater(service.readFnLockMode(), throwsFormatException);
    },
  );

  test(
    'LED discovery matches function, follows links and preserves legacy off',
    () async {
      write('sys/class/leds/unrelated/brightness', 1);
      expect(await service.readWhiteKeyboardBacklightMode(), isNull);
      write('devices/keyboard/brightness', 2);
      Link(
        '${root.path}/sys/class/leds/ideapad::kbd_backlight',
      ).createSync('${root.path}/devices/keyboard');
      write('sys/class/leds/zvendor::kbd_backlight/brightness', 0);
      write('sys/class/leds/legion::ylogo/brightness', 1);
      write('sys/class/leds/legion::ioport/brightness', 0);
      expect(await service.readWhiteKeyboardBacklightMode(), isTrue);
      expect(await service.readYLogoLightMode(), isTrue);
      expect(await service.readIoPortLightMode(), isFalse);
      write('sys/class/leds/platform::kbd_backlight/brightness', 0);
      write('sys/class/leds/platform::ylogo/brightness', 0);
      write('sys/class/leds/platform::ioport/brightness', 1);
      expect(await service.readWhiteKeyboardBacklightMode(), isFalse);
      expect(await service.readYLogoLightMode(), isFalse);
      expect(await service.readIoPortLightMode(), isTrue);
    },
  );

  test(
    'default Legion platform paths relocate and retain fallback order',
    () async {
      const driver = 'sys/module/legion_laptop/drivers/platform:legion';
      write('$driver/PNP0C09:00/gsync', 1);
      write('$driver/PNP0C09:00/touchpad', 1);
      write('$driver/PNP0C09:00/hwmon/hwmon0/fan1_input', 3500);
      expect(await service.readHybridMode(), isTrue);
      expect(await service.readTouchpadMode(), isTrue);
      expect(await service.readFan1Rpm(), 3500);
      write('$driver/legion/gsync', 0);
      write('$driver/legion/hwmon/hwmon0/fan1_input', 4000);
      expect(await service.readHybridMode(), isFalse);
      expect(await service.readFan1Rpm(), 4000);
    },
  );
}
