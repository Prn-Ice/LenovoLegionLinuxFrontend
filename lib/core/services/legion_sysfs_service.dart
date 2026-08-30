import 'dart:convert';
import 'dart:io';

import '../../features/fans/models/fan_curve.dart';
import '../../features/dashboard/models/system_status.dart';
import '../models/cpu_policy_snapshot.dart';

class LegionSysfsService {
  static const String _hwmonBasePath = '/sys/class/hwmon';
  static const List<String> _defaultLegionPlatformRoots = [
    '/sys/module/legion_laptop/drivers/platform:legion/legion',
    '/sys/module/legion_laptop/drivers/platform:legion/PNP0C09:00',
  ];

  /// The roots are injectable to make sysfs discovery testable.  In normal
  /// use they retain their kernel-provided locations.
  final String _hwmonRoot;
  final List<String> _legionPlatformRoots;
  final List<String> _fanHwmonRoots;
  final String _cpuPolicyRoot;
  final String _amdPstateRoot;
  final String _cpuFreqRoot;

  LegionSysfsService({
    String hwmonRoot = _hwmonBasePath,
    List<String> legionPlatformRoots = _defaultLegionPlatformRoots,
    String? fanHwmonRoot,
    String cpuPolicyRoot = '/sys/devices/system/cpu/cpufreq/policy0',
    String amdPstateRoot = '/sys/devices/system/cpu/amd_pstate',
    String cpuFreqRoot = '/sys/devices/system/cpu/cpufreq',
  }) : _hwmonRoot = hwmonRoot,
       _legionPlatformRoots = legionPlatformRoots,
       _fanHwmonRoots = fanHwmonRoot == null
           ? [for (final root in legionPlatformRoots) '$root/hwmon']
           : [fanHwmonRoot],
       _cpuPolicyRoot = cpuPolicyRoot,
       _amdPstateRoot = amdPstateRoot,
       _cpuFreqRoot = cpuFreqRoot;

  /// Convert hwmon millidegrees Celsius to degrees Celsius.
  static double milliDegreesToC(int milliDegrees) => milliDegrees / 1000.0;

  static const String _platformProfilePath =
      '/sys/firmware/acpi/platform_profile';
  static const String _platformProfileChoicesPath =
      '/sys/firmware/acpi/platform_profile_choices';
  static const String _batteryConservationPath =
      '/sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/conservation_mode';
  static const String _alwaysOnUsbChargingPath =
      '/sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/usb_charging';
  static const String _touchpadIdeapadPath =
      '/sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/touchpad';
  static const String _cameraPowerPath =
      '/sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/camera_power';
  static const String _fnLockPath =
      '/sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/fn_lock';
  static const String _whiteKeyboardBacklightPath =
      '/sys/class/leds/platform::kbd_backlight/brightness';
  static const String _yLogoLightPath =
      '/sys/class/leds/platform::ylogo/brightness';
  static const String _ioPortLightPath =
      '/sys/class/leds/platform::ioport/brightness';
  static const String _onPowerSupplyAdp0Path =
      '/sys/class/power_supply/ADP0/online';
  static const String _onPowerSupplyAcPath =
      '/sys/class/power_supply/AC/online';

  static const String _legacyBatteryPath = '/sys/class/power_supply/BAT0';

  final Map<String, String?> _powerSupplyDirCache = {};
  static const String _dmiPath = '/sys/class/dmi/id';

  Future<SystemStatus> readSystemStatus() async {
    try {
      final powerProfile = await readPlatformProfile();
      return SystemStatus(
        updatedAt: DateTime.now(),
        powerProfile: powerProfile,
        error: powerProfile == null
            ? 'platform_profile is not available on this system.'
            : null,
      );
    } catch (error) {
      return SystemStatus(
        updatedAt: DateTime.now(),
        error: 'Failed to read system status: $error',
      );
    }
  }

  Future<String?> readPlatformProfile() async {
    return _readTrimmedFile(_platformProfilePath);
  }

  Future<List<String>> readPlatformProfileChoices() async {
    final raw = await _readTrimmedFile(_platformProfileChoicesPath);
    if (raw == null || raw.isEmpty) {
      return const [];
    }

    final values = <String>[];
    for (final token in raw.split(RegExp(r'\s+'))) {
      final cleaned = token.replaceAll('[', '').replaceAll(']', '').trim();
      if (cleaned.isEmpty || values.contains(cleaned)) {
        continue;
      }
      values.add(cleaned);
    }

    return values;
  }

  Future<bool?> readHybridMode() async {
    return _readLegionBoolFile('gsync');
  }

  Future<bool?> readOverdriveMode() async {
    return _readLegionBoolFile('overdrive');
  }

  Future<bool?> readBatteryConservationMode() async {
    return _readBoolFile(_batteryConservationPath);
  }

  Future<bool?> readRapidChargingMode() async {
    return _readLegionBoolFile('rapidcharge');
  }

  Future<bool?> readAlwaysOnUsbChargingMode() async {
    return _readBoolFile(_alwaysOnUsbChargingPath);
  }

  Future<bool?> readTouchpadMode() async {
    return _readBoolFromPaths([
      _touchpadIdeapadPath,
      ..._legionPaths('touchpad'),
    ]);
  }

  Future<bool?> readWinKeyMode() async {
    return _readLegionBoolFile('winkey');
  }

  Future<bool?> readCameraPowerMode() async {
    return _readBoolFile(_cameraPowerPath);
  }

  Future<bool?> readFnLockMode() async {
    return _readBoolFile(_fnLockPath);
  }

  Future<bool?> readWhiteKeyboardBacklightMode() async {
    return _readEnabledFromBrightnessFile(_whiteKeyboardBacklightPath);
  }

  Future<bool?> readYLogoLightMode() async {
    return _readEnabledFromBrightnessFile(_yLogoLightPath);
  }

  Future<bool?> readIoPortLightMode() async {
    return _readEnabledFromBrightnessFile(_ioPortLightPath);
  }

  Future<bool?> readOnPowerSupplyMode() async {
    final acDir = await _powerSupplyDirOfType('Mains');
    if (acDir != null) {
      final online = await readIntFile('$acDir/online');
      if (online != null) return online == 1;
    }
    return _readBoolFromPaths([_onPowerSupplyAdp0Path, _onPowerSupplyAcPath]);
  }

  /// Battery charge percentage (0–100) from the discovered battery supply.
  Future<int?> readBatteryPercent() async =>
      readIntFile('${await _batteryBase()}/capacity');

  /// Battery charge status (e.g. 'Charging', 'Discharging', 'Full').
  Future<String?> readBatteryStatus() async =>
      _readTrimmedFile('${await _batteryBase()}/status');

  /// Base dir of the first Battery-type power supply (BAT0, BAT1, …), falling
  /// back to the legacy fixed path when discovery finds nothing.
  Future<String> _batteryBase() async =>
      (await _powerSupplyDirOfType('Battery')) ?? _legacyBatteryPath;

  /// First `/sys/class/power_supply/*` whose `type` equals [type] (e.g.
  /// 'Battery', 'Mains'). Cached per type so the directory scan runs once.
  Future<String?> _powerSupplyDirOfType(String type) async {
    if (_powerSupplyDirCache.containsKey(type)) {
      return _powerSupplyDirCache[type];
    }
    String? found;
    try {
      final root = Directory('/sys/class/power_supply');
      if (root.existsSync()) {
        for (final entry in root.listSync()) {
          if (await _readTrimmedFile('${entry.path}/type') == type) {
            found = entry.path;
            break;
          }
        }
      }
    } catch (_) {}
    _powerSupplyDirCache[type] = found;
    return found;
  }

  Future<bool?> readLockFanControllerMode() async {
    return _readLegionBoolFile('lockfancontroller');
  }

  Future<bool?> readMaximumFanSpeedMode() async {
    return _readLegionBoolFile('fan_fullspeed');
  }

  Future<bool?> readMiniFanCurveMode() async {
    final hwmonPath = await _findFanHwmonDir();
    if (hwmonPath == null) {
      return null;
    }

    return _readBoolFile('${hwmonPath}minifancurve');
  }

  Future<FanCurve?> readFanCurve() async {
    final hwmonPath = await _findFanHwmonDir();
    if (hwmonPath == null) {
      return null;
    }

    final fan1Max = await readIntFile('${hwmonPath}fan1_max');
    final fan2Max = await readIntFile('${hwmonPath}fan2_max');

    if (fan1Max == null || fan1Max <= 0 || fan2Max == null || fan2Max <= 0) {
      return null;
    }

    final points = <FanCurvePoint>[];
    for (var i = 1; i <= 10; i++) {
      final values = await Future.wait([
        readIntFile('${hwmonPath}pwm1_auto_point${i}_pwm'),
        readIntFile('${hwmonPath}pwm2_auto_point${i}_pwm'),
        readIntFile('${hwmonPath}pwm1_auto_point${i}_temp_hyst'),
        readIntFile('${hwmonPath}pwm1_auto_point${i}_temp'),
        readIntFile('${hwmonPath}pwm2_auto_point${i}_temp_hyst'),
        readIntFile('${hwmonPath}pwm2_auto_point${i}_temp'),
        readIntFile('${hwmonPath}pwm3_auto_point${i}_temp_hyst'),
        readIntFile('${hwmonPath}pwm3_auto_point${i}_temp'),
        readIntFile('${hwmonPath}pwm1_auto_point${i}_accel'),
        readIntFile('${hwmonPath}pwm1_auto_point${i}_decel'),
      ]);
      if (values.any((value) => value == null)) return null;
      final [
        pwm1!,
        pwm2!,
        cpuLower!,
        cpuUpper!,
        gpuLower!,
        gpuUpper!,
        icLower!,
        icUpper!,
        accel!,
        decel!,
      ] = values;
      if (!_validPwm(pwm1) ||
          !_validPwm(pwm2) ||
          !_validTemperatureRange(cpuLower, cpuUpper) ||
          !_validTemperatureRange(gpuLower, gpuUpper) ||
          !_validTemperatureRange(icLower, icUpper)) {
        return null;
      }

      points.add(
        FanCurvePoint(
          fan1Rpm: _pwmToRpm(pwm1, fan1Max),
          fan2Rpm: _pwmToRpm(pwm2, fan2Max),
          cpuLowerTemp: cpuLower,
          cpuUpperTemp: cpuUpper,
          gpuLowerTemp: gpuLower,
          gpuUpperTemp: gpuUpper,
          icLowerTemp: icLower,
          icUpperTemp: icUpper,
          accel: accel,
          decel: decel,
        ),
      );
    }

    if (!_usableFanCurve(points)) return null;
    return FanCurve(
      name: 'custom',
      points: List.unmodifiable(points),
      fan1MaxRpm: fan1Max,
      fan2MaxRpm: fan2Max,
    );
  }

  Future<bool?> readCpuOverclockMode() async {
    return _readLegionBoolFile('cpu_oc');
  }

  Future<bool?> readGpuOverclockMode() async {
    return _readLegionBoolFile('gpu_oc');
  }

  /// Current CPU fan speed in RPM. Returns null if unavailable.
  Future<int?> readFan1Rpm() async {
    return _readFanRpm(1);
  }

  /// Current GPU fan speed in RPM. Returns null if unavailable.
  Future<int?> readFan2Rpm() async {
    return _readFanRpm(2);
  }

  Future<int?> readFan1MaxRpm() => _readFanMaxRpm(1);

  Future<int?> readFan2MaxRpm() => _readFanMaxRpm(2);

  /// CPU package temperature in °C. Returns null if unavailable.
  Future<double?> readCpuTempC() async {
    // legion_hwmon's labeled CPU sensor is the controller's dedicated CPU
    // reading and avoids presenting the same ACPI temperature as the system.
    var path = await _findHwmonTempInput(
      driverNames: {'legion_hwmon'},
      label: 'CPU Temperature',
    );
    // Prefer the dedicated CPU sensor (Intel coretemp / AMD k10temp).
    path ??= await _findHwmonTempInput(
      driverNames: {'coretemp', 'k10temp'},
      label: 'Package id 0',
      fallbackIndex: 1,
    );
    final raw = path == null ? null : await readIntFile(path);
    return raw == null ? null : milliDegreesToC(raw);
  }

  /// GPU temperature in °C. Returns null if unavailable.
  Future<double?> readGpuTempC() async {
    final path = await _findHwmonTempInput(
      driverNames: {'nouveau', 'amdgpu', 'nvidia', 'radeon'},
      fallbackIndex: 1,
    );
    final raw = path == null ? null : await readIntFile(path);
    return raw == null ? null : milliDegreesToC(raw);
  }

  // ── CPU utilisation ──────────────────────────────────────────────────────

  /// CPU utilisation percentage (0–100). Computed from /proc/stat deltas.
  /// Returns null if /proc/stat is not readable.
  Future<double?> readCpuUtilisationPercent() async {
    try {
      final line1 = await _readFirstCpuStatLine();
      if (line1 == null) return null;
      await Future.delayed(const Duration(milliseconds: 200));
      final line2 = await _readFirstCpuStatLine();
      if (line2 == null) return null;

      final fields1 = line1
          .split(RegExp(r'\s+'))
          .skip(1)
          .map(int.parse)
          .toList();
      final fields2 = line2
          .split(RegExp(r'\s+'))
          .skip(1)
          .map(int.parse)
          .toList();

      final idle1 = fields1.length > 3 ? fields1[3] : 0;
      final idle2 = fields2.length > 3 ? fields2[3] : 0;
      final total1 = fields1.fold(0, (a, b) => a + b);
      final total2 = fields2.fold(0, (a, b) => a + b);

      final totalDelta = total2 - total1;
      final idleDelta = idle2 - idle1;

      if (totalDelta <= 0) return null;

      return (1.0 - idleDelta / totalDelta) * 100.0;
    } catch (_) {
      return null;
    }
  }

  // ── CPU clock ─────────────────────────────────────────────────────────────

  /// Effective policy for the first CPU frequency domain. PPD applies the same
  /// policy across every domain, so policy0 is sufficient for display.
  Future<CpuPolicySnapshot?> readCpuPolicySnapshot() async {
    final driver = await _readTrimmedFile('$_cpuPolicyRoot/scaling_driver');
    final pstateStatus = await _readTrimmedFile('$_amdPstateRoot/status');
    final governor = await _readTrimmedFile('$_cpuPolicyRoot/scaling_governor');
    final energyPreference = await _readTrimmedFile(
      '$_cpuPolicyRoot/energy_performance_preference',
    );
    final policyBoost = await _readOptionalBoolFile('$_cpuPolicyRoot/boost');
    final globalBoost =
        policyBoost ?? await _readOptionalBoolFile('$_cpuFreqRoot/boost');
    final minimumFrequency = await readIntFile(
      '$_cpuPolicyRoot/scaling_min_freq',
    );
    final maximumFrequency = await readIntFile(
      '$_cpuPolicyRoot/scaling_max_freq',
    );

    final snapshot = CpuPolicySnapshot(
      driver: driver,
      pstateStatus: pstateStatus,
      governor: governor,
      energyPerformancePreference: energyPreference,
      boostEnabled: globalBoost,
      minimumFrequencyKhz: minimumFrequency,
      maximumFrequencyKhz: maximumFrequency,
    );
    return snapshot.hasData ? snapshot : null;
  }

  /// Average clock speed across all online CPUs in GHz.
  Future<double?> readAverageCpuClockGhz() async {
    try {
      final cpuDir = Directory('/sys/devices/system/cpu');
      if (!await cpuDir.exists()) return null;

      final clocks = <int>[];
      await for (final entity in cpuDir.list()) {
        if (entity is! Directory) continue;
        final name = entity.path.split('/').last;
        if (!RegExp(r'^cpu\d+$').hasMatch(name)) continue;
        final freqPath = '${entity.path}/cpufreq/scaling_cur_freq';
        final val = await readIntFile(freqPath);
        if (val != null && val > 0) clocks.add(val);
      }
      if (clocks.isEmpty) return null;
      final avgKhz = clocks.fold(0, (a, b) => a + b) / clocks.length;
      return avgKhz / 1e6; // kHz → GHz
    } catch (_) {
      return null;
    }
  }

  // ── Battery detail ────────────────────────────────────────────────────────

  /// Battery cycle count from /sys/class/power_supply/BAT0/cycle_count.
  Future<int?> readBatteryCycleCount() async {
    return readIntFile('${await _batteryBase()}/cycle_count');
  }

  /// Battery full charge capacity in Wh.
  Future<double?> readBatteryFullCapacityWh() async {
    final energyFull = await readIntFile('${await _batteryBase()}/energy_full');
    if (energyFull != null) return energyFull / 1e6;
    final chargeFull = await readIntFile('${await _batteryBase()}/charge_full');
    final voltageNow = await readIntFile('${await _batteryBase()}/voltage_now');
    if (chargeFull != null && voltageNow != null) {
      return (chargeFull / 1e6) * (voltageNow / 1e6);
    }
    return null;
  }

  /// Battery design capacity in Wh.
  Future<double?> readBatteryDesignCapacityWh() async {
    final energyDesign = await readIntFile(
      '${await _batteryBase()}/energy_full_design',
    );
    if (energyDesign != null) return energyDesign / 1e6;
    final chargeDesign = await readIntFile(
      '${await _batteryBase()}/charge_full_design',
    );
    final voltageNow = await readIntFile('${await _batteryBase()}/voltage_now');
    if (chargeDesign != null && voltageNow != null) {
      return (chargeDesign / 1e6) * (voltageNow / 1e6);
    }
    return null;
  }

  /// Battery current capacity in Wh.
  Future<double?> readBatteryCurrentCapacityWh() async {
    final energyNow = await readIntFile('${await _batteryBase()}/energy_now');
    if (energyNow != null) return energyNow / 1e6;
    final chargeNow = await readIntFile('${await _batteryBase()}/charge_now');
    final voltageNow = await readIntFile('${await _batteryBase()}/voltage_now');
    if (chargeNow != null && voltageNow != null) {
      return (chargeNow / 1e6) * (voltageNow / 1e6);
    }
    return null;
  }

  /// Battery power draw in watts (positive = discharging, negative = charging).
  Future<double?> readBatteryPowerDrawW() async {
    final powerNow = await readIntFile('${await _batteryBase()}/power_now');
    if (powerNow != null) {
      final status = await _readTrimmedFile('${await _batteryBase()}/status');
      final sign = status == 'Charging' ? -1.0 : 1.0;
      return sign * powerNow / 1e6;
    }
    final currentNow = await readIntFile('${await _batteryBase()}/current_now');
    final voltageNow = await readIntFile('${await _batteryBase()}/voltage_now');
    if (currentNow != null && voltageNow != null) {
      final status = await _readTrimmedFile('${await _batteryBase()}/status');
      final sign = status == 'Charging' ? -1.0 : 1.0;
      return sign * (currentNow / 1e6) * (voltageNow / 1e6);
    }
    return null;
  }

  /// Battery temperature in °C (from power_supply temp file, tenths of °C).
  Future<double?> readBatteryTempC() async {
    final raw = await readIntFile('${await _batteryBase()}/temp');
    if (raw != null) return raw / 10.0;
    return null;
  }

  Future<double?> readBatteryVoltageV() async {
    final raw = await readIntFile('${await _batteryBase()}/voltage_now');
    return raw == null ? null : raw / 1e6;
  }

  Future<String?> readBatteryManufacturer() async =>
      _readTrimmedFile('${await _batteryBase()}/manufacturer');

  Future<String?> readBatteryModelName() async =>
      _readTrimmedFile('${await _batteryBase()}/model_name');

  Future<String?> readBatterySerialNumber() async =>
      _readTrimmedFile('${await _batteryBase()}/serial_number');

  // ── Board / disk temperatures ─────────────────────────────────────────────

  /// Motherboard temperature in °C via hwmon (e.g. acpitz, it87, nct6775).
  Future<double?> readMotherboardTempC() async {
    final path = await _findHwmonTempInput(
      driverNames: {'acpitz', 'it87', 'nct6775', 'nct6776', 'nct6779'},
      fallbackIndex: 1,
    );
    final raw = path == null ? null : await readIntFile(path);
    return raw == null ? null : milliDegreesToC(raw);
  }

  /// Primary disk temperature in °C via hwmon (NVMe or SATA).
  Future<double?> readDiskTempC() async {
    final path = await _findHwmonTempInput(
      driverNames: {'nvme', 'drivetemp'},
      fallbackIndex: 1,
    );
    final raw = path == null ? null : await readIntFile(path);
    return raw == null ? null : milliDegreesToC(raw);
  }

  // ── Device identity (DMI) ─────────────────────────────────────────────────

  Future<String?> readDeviceProductFamily() async =>
      _readTrimmedFile('$_dmiPath/product_family');

  Future<String?> readDeviceProductName() async =>
      _readTrimmedFile('$_dmiPath/product_name');

  Future<String?> readDeviceSerial() async =>
      _readTrimmedFile('$_dmiPath/product_serial');

  Future<String?> readBiosVersion() async =>
      _readTrimmedFile('$_dmiPath/bios_version');

  // ── CPU identity ──────────────────────────────────────────────────────────

  /// CPU model name from /proc/cpuinfo.
  Future<String?> readCpuName() async {
    try {
      final file = File('/proc/cpuinfo');
      if (!await file.exists()) return null;
      await for (final line
          in file
              .openRead()
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        if (line.startsWith('model name')) {
          final parts = line.split(':');
          if (parts.length >= 2) return parts.sublist(1).join(':').trim();
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  /// Kernel release string, e.g. `7.0.12`.
  Future<String?> readKernelRelease() async =>
      _readTrimmedFile('/proc/sys/kernel/osrelease');

  /// legion_laptop module version, or null when the module is absent.
  Future<String?> readLegionModuleVersion() async =>
      _readTrimmedFile('/sys/module/legion_laptop/version');

  /// System uptime in seconds, or null if unreadable.
  Future<int?> readUptimeSeconds() async {
    final raw = await _readTrimmedFile('/proc/uptime');
    if (raw == null) return null;
    final first = raw.split(RegExp(r'\s+')).first;
    return double.tryParse(first)?.round();
  }

  Future<String?> _findHwmonTempInput({
    required Set<String> driverNames,
    String? label,
    int fallbackIndex = 1,
  }) async {
    final dir = Directory(_hwmonRoot);
    if (!await dir.exists()) return null;
    try {
      await for (final entity in dir.list(followLinks: true)) {
        if (entity is! Directory) continue;
        final nameFile = File('${entity.path}/name');
        if (!await nameFile.exists()) continue;
        final name = (await nameFile.readAsString()).trim().toLowerCase();
        if (!driverNames.contains(name)) continue;
        if (label != null) {
          for (var i = 1; i <= 32; i++) {
            final lf = File('${entity.path}/temp${i}_label');
            if (!await lf.exists()) continue;
            if ((await lf.readAsString()).trim() == label) {
              return '${entity.path}/temp${i}_input';
            }
          }
        }
        final fb = '${entity.path}/temp${fallbackIndex}_input';
        if (await File(fb).exists()) return fb;
      }
    } catch (_) {}
    return null;
  }

  Future<String?> _findFanHwmonDir() async {
    for (final root in _fanHwmonRoots) {
      final hwmonDir = Directory(root);
      if (!await hwmonDir.exists()) {
        continue;
      }

      try {
        // The legion driver's hwmon entries are commonly symlinks into
        // /sys/class/hwmon. Follow them instead of discarding them as Links.
        await for (final entity in hwmonDir.list(followLinks: true)) {
          if (entity is! Directory) {
            continue;
          }

          final name = entity.path.split('/').last;
          if (name.startsWith('hwmon')) {
            return '${entity.path}/';
          }
        }
      } catch (_) {
        continue;
      }
    }

    return null;
  }

  List<String> _legionPaths(String attribute) => [
    for (final root in _legionPlatformRoots) '$root/$attribute',
  ];

  Future<bool?> _readLegionBoolFile(String attribute) =>
      _readBoolFromPaths(_legionPaths(attribute));

  Future<int?> readLegionIntFile(String attribute) async {
    for (final path in _legionPaths(attribute)) {
      final value = await readIntFile(path);
      if (value != null) return value;
    }
    return null;
  }

  Future<int?> _readFanRpm(int fanNumber) async {
    // Keep the legion controller as the preferred source: it is also the
    // source used for curve control. Some kernels expose live RPMs only from
    // a separate hwmon provider (for example yogafan), however.
    final controller = await _findFanHwmonDir();
    if (controller != null) {
      final rpm = await readIntFile('${controller}fan${fanNumber}_input');
      if (rpm != null) return rpm;
    }

    final root = Directory(_hwmonRoot);
    if (!await root.exists()) return null;
    try {
      await for (final entity in root.list(followLinks: true)) {
        if (entity is! Directory) continue;
        final input = File('${entity.path}/fan${fanNumber}_input');
        if (!await input.exists()) continue;
        final rpm = await readIntFile(input.path);
        if (rpm != null) return rpm;
      }
    } catch (_) {}
    return null;
  }

  Future<int?> _readFanMaxRpm(int fanNumber) async {
    final controller = await _findFanHwmonDir();
    if (controller == null) return null;
    final value = await readIntFile('${controller}fan${fanNumber}_max');
    return value == null || value <= 0 ? null : value;
  }

  Future<String?> _readFirstCpuStatLine() async {
    try {
      final file = File('/proc/stat');
      if (!await file.exists()) return null;
      final lines = await file.readAsLines();
      return lines.firstWhere((l) => l.startsWith('cpu '), orElse: () => '');
    } catch (_) {
      return null;
    }
  }

  static int _pwmToRpm(int pwm, int maxRpm) {
    return (pwm / 255.0 * maxRpm).round();
  }

  static bool _validPwm(int value) => value >= 0 && value <= 255;

  static bool _validTemperatureRange(int lower, int upper) =>
      lower >= 0 && upper >= lower && upper <= 120;

  static bool _usableFanCurve(List<FanCurvePoint> points) {
    if (points.isEmpty ||
        points.every((point) => point.cpuUpperTemp == 0) ||
        points.every((point) => point.gpuUpperTemp == 0) ||
        points.every((point) => point.fan1Rpm == 0) ||
        points.every((point) => point.fan2Rpm == 0)) {
      return false;
    }
    // A present-but-zero legion_hwmon table is not a usable curve. Treat the
    // whole table as unavailable rather than rendering a collapsed editor.
    // Reject a present-but-zero table through the semantic checks above: a
    // usable curve needs non-zero temperature and PWM channels.
    for (var i = 1; i < points.length; i++) {
      final previous = points[i - 1];
      final current = points[i];
      if (current.cpuUpperTemp < previous.cpuUpperTemp ||
          current.gpuUpperTemp < previous.gpuUpperTemp ||
          current.fan1Rpm < previous.fan1Rpm ||
          current.fan2Rpm < previous.fan2Rpm) {
        return false;
      }
    }
    return true;
  }

  Future<int?> readIntFile(String path) async {
    try {
      final raw = await _readTrimmedFile(path);
      if (raw == null) {
        return null;
      }

      return int.tryParse(raw);
    } catch (_) {
      return null;
    }
  }

  Future<bool?> _readBoolFromPaths(List<String> paths) async {
    for (final path in paths) {
      final value = await _readBoolFile(path);
      if (value != null) {
        return value;
      }
    }
    return null;
  }

  Future<bool?> _readBoolFile(String path) async {
    final raw = await _readTrimmedFile(path);
    if (raw == null) {
      return null;
    }

    final normalized = raw.trim().toLowerCase();
    if (normalized == '1' || normalized == 'true') {
      return true;
    }
    if (normalized == '0' || normalized == 'false') {
      return false;
    }

    throw FormatException('Unexpected bool value "$raw" at $path');
  }

  Future<bool?> _readOptionalBoolFile(String path) async {
    try {
      return await _readBoolFile(path);
    } on FormatException {
      return null;
    }
  }

  Future<bool?> _readEnabledFromBrightnessFile(String path) async {
    final value = await readIntFile(path);
    if (value == null) {
      return null;
    }

    return value > 0;
  }

  Future<String?> _readTrimmedFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        return null;
      }

      final value = (await file.readAsString()).trim();
      return value.isEmpty ? null : value;
    } on FileSystemException {
      return null;
    }
  }
}
