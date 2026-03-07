import 'dart:io';

import '../../features/fans/models/fan_curve.dart';
import '../../features/dashboard/models/system_status.dart';

class LegionSysfsService {
  static const String _platformProfilePath =
      '/sys/firmware/acpi/platform_profile';
  static const String _platformProfileChoicesPath =
      '/sys/firmware/acpi/platform_profile_choices';
  static const String _hybridModePath =
      '/sys/module/legion_laptop/drivers/platform:legion/PNP0C09:00/gsync';
  static const String _overdrivePath =
      '/sys/module/legion_laptop/drivers/platform:legion/PNP0C09:00/overdrive';

  static const String _batteryConservationPath =
      '/sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/conservation_mode';
  static const String _rapidChargingPath =
      '/sys/module/legion_laptop/drivers/platform:legion/PNP0C09:00/rapidcharge';
  static const String _alwaysOnUsbChargingPath =
      '/sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/usb_charging';
  static const String _touchpadIdeapadPath =
      '/sys/bus/platform/drivers/ideapad_acpi/VPC2004:00/touchpad';
  static const String _touchpadLegionPath =
      '/sys/module/legion_laptop/drivers/platform:legion/PNP0C09:00/touchpad';
  static const String _winKeyPath =
      '/sys/module/legion_laptop/drivers/platform:legion/PNP0C09:00/winkey';
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

  static const String _lockFanControllerPath =
      '/sys/module/legion_laptop/drivers/platform:legion/PNP0C09:00/lockfancontroller';
  static const String _maximumFanSpeedPath =
      '/sys/module/legion_laptop/drivers/platform:legion/PNP0C09:00/fan_fullspeed';
  static const String _fanHwmonBasePath =
      '/sys/module/legion_laptop/drivers/platform:legion/PNP0C09:00/hwmon';
  static const String _cpuOverclockPath =
      '/sys/module/legion_laptop/drivers/platform:legion/PNP0C09:00/cpu_oc';
  static const String _gpuOverclockPath =
      '/sys/module/legion_laptop/drivers/platform:legion/PNP0C09:00/gpu_oc';

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
    return _readBoolFile(_hybridModePath);
  }

  Future<bool?> readOverdriveMode() async {
    return _readBoolFile(_overdrivePath);
  }

  Future<bool?> readBatteryConservationMode() async {
    return _readBoolFile(_batteryConservationPath);
  }

  Future<bool?> readRapidChargingMode() async {
    return _readBoolFile(_rapidChargingPath);
  }

  Future<bool?> readAlwaysOnUsbChargingMode() async {
    return _readBoolFile(_alwaysOnUsbChargingPath);
  }

  Future<bool?> readTouchpadMode() async {
    return _readBoolFromPaths([_touchpadIdeapadPath, _touchpadLegionPath]);
  }

  Future<bool?> readWinKeyMode() async {
    return _readBoolFile(_winKeyPath);
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
    return _readBoolFromPaths([_onPowerSupplyAdp0Path, _onPowerSupplyAcPath]);
  }

  Future<bool?> readLockFanControllerMode() async {
    return _readBoolFile(_lockFanControllerPath);
  }

  Future<bool?> readMaximumFanSpeedMode() async {
    return _readBoolFile(_maximumFanSpeedPath);
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

    if (fan1Max == null || fan1Max == 0 || fan2Max == null || fan2Max == 0) {
      return null;
    }

    final points = <FanCurvePoint>[];
    for (var i = 1; i <= 10; i++) {
      final pwm1 = (await readIntFile('${hwmonPath}pwm1_auto_point${i}_pwm')) ?? 0;
      final pwm2 = (await readIntFile('${hwmonPath}pwm2_auto_point${i}_pwm')) ?? 0;
      final cpuLower =
          (await readIntFile('${hwmonPath}pwm1_auto_point${i}_temp_hyst')) ?? 0;
      final cpuUpper = (await readIntFile('${hwmonPath}pwm1_auto_point${i}_temp')) ?? 0;
      final gpuLower =
          (await readIntFile('${hwmonPath}pwm2_auto_point${i}_temp_hyst')) ?? 0;
      final gpuUpper = (await readIntFile('${hwmonPath}pwm2_auto_point${i}_temp')) ?? 0;
      final icLower =
          (await readIntFile('${hwmonPath}pwm3_auto_point${i}_temp_hyst')) ?? 0;
      final icUpper = (await readIntFile('${hwmonPath}pwm3_auto_point${i}_temp')) ?? 0;
      final accel = (await readIntFile('${hwmonPath}pwm1_auto_point${i}_accel')) ?? 0;
      final decel = (await readIntFile('${hwmonPath}pwm1_auto_point${i}_decel')) ?? 0;

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

    return FanCurve(name: 'custom', points: List.unmodifiable(points));
  }

  Future<bool?> readCpuOverclockMode() async {
    return _readBoolFile(_cpuOverclockPath);
  }

  Future<bool?> readGpuOverclockMode() async {
    return _readBoolFile(_gpuOverclockPath);
  }

  Future<String?> _findFanHwmonDir() async {
    final hwmonDir = Directory(_fanHwmonBasePath);
    if (!await hwmonDir.exists()) {
      return null;
    }

    try {
      await for (final entity in hwmonDir.list(followLinks: false)) {
        if (entity is! Directory) {
          continue;
        }

        final name = entity.path.split('/').last;
        if (name.startsWith('hwmon')) {
          return '${entity.path}/';
        }
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  static int _pwmToRpm(int pwm, int maxRpm) {
    return (pwm / 255.0 * maxRpm).round();
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
