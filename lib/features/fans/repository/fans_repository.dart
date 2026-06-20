import 'dart:io';

import '../../../core/data/privileged_repository.dart';
import '../../../core/services/legion_sysfs_service.dart';
import '../models/fan_curve.dart';
import '../models/fans_snapshot.dart';

class FansRepositoryException implements Exception {
  const FansRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FansRepository extends PrivilegedRepository {
  const FansRepository({
    required LegionSysfsService sysfsService,
    required super.bridgeService,
  }) : _sysfsService = sysfsService;

  @override
  Exception wrapBridgeError(String message) => FansRepositoryException(message);

  final LegionSysfsService _sysfsService;

  static const List<String> defaultPresets = [
    'quiet-battery',
    'balanced-battery',
    'performance-battery',
    'balanced-performance-battery',
    'quiet-ac',
    'balanced-ac',
    'performance-ac',
    'balanced-performance-ac',
  ];
  static const _tempCurvePath = '/tmp/legion_frontend_custom_curve.yaml';

  Future<FansSnapshot> loadSnapshot() async {
    final profile = await _sysfsService.readPlatformProfile();
    final onPowerSupply = await _sysfsService.readOnPowerSupplyMode();

    final recommendedPreset = _computeRecommendedPreset(
      profile: profile,
      onPowerSupply: onPowerSupply,
    );

    final miniFanCurve = await _sysfsService.readMiniFanCurveMode();
    final lockFanController = await _sysfsService.readLockFanControllerMode();
    final maximumFanSpeed = await _sysfsService.readMaximumFanSpeedMode();
    final fanCurve = await _sysfsService.readFanCurve();

    return FansSnapshot(
      platformProfile: profile,
      onPowerSupply: onPowerSupply,
      recommendedPreset: recommendedPreset,
      availablePresets: defaultPresets,
      miniFanCurveEnabled: miniFanCurve,
      lockFanControllerEnabled: lockFanController,
      maximumFanSpeedEnabled: maximumFanSpeed,
      fanCurve: fanCurve,
    );
  }

  Future<void> applyCurrentContextPreset() async {
    await runPrivilegedCommand(
      ['fancurve-write-current-preset-to-hw'],
      method: 'fan_curve.apply_context_preset',
      failurePrefix: 'Failed to apply current context fan preset',
    );
  }

  Future<void> applyPreset(String presetName) async {
    await runPrivilegedCommand(
      ['fancurve-write-preset-to-hw', presetName],
      method: 'fan_curve.apply_preset',
      failurePrefix: 'Failed to apply fan preset "$presetName"',
    );
  }

  Future<void> setMiniFanCurve(bool enabled) async {
    final command = enabled ? 'minifancurve-enable' : 'minifancurve-disable';
    await runPrivilegedCommand(
      [command],
      method: 'mini_fan_curve.set',
      failurePrefix:
          'Failed to set mini fan curve to ${enabled ? 'on' : 'off'}',
    );
  }

  Future<void> setLockFanController(bool enabled) async {
    final command = enabled
        ? 'lockfancontroller-enable'
        : 'lockfancontroller-disable';
    await runPrivilegedCommand(
      [command],
      method: 'lock_fan_controller.set',
      failurePrefix:
          'Failed to set lock fan controller to ${enabled ? 'on' : 'off'}',
    );
  }

  Future<void> setMaximumFanSpeed(bool enabled) async {
    final command = enabled
        ? 'maximumfanspeed-enable'
        : 'maximumfanspeed-disable';
    await runPrivilegedCommand(
      [command],
      method: 'maximum_fan_speed.set',
      failurePrefix:
          'Failed to set maximum fan speed to ${enabled ? 'on' : 'off'}',
    );
  }

  Future<void> writeFanCurveToHardware(FanCurve curve) async {
    try {
      await File(_tempCurvePath).writeAsString(curve.toYaml());
    } catch (error) {
      throw FansRepositoryException(
        'Failed to write fan curve temp file: $error',
      );
    }

    await runPrivilegedCommand(
      ['fancurve-write-file-to-hw', _tempCurvePath],
      method: 'fan_curve.write_to_hw',
      failurePrefix: 'Failed to write fan curve to hardware',
    );
  }

  String? _computeRecommendedPreset({
    required String? profile,
    required bool? onPowerSupply,
  }) {
    if (profile == null || onPowerSupply == null) {
      return null;
    }

    final suffix = onPowerSupply ? 'ac' : 'battery';
    final preset = '$profile-$suffix';

    if (!defaultPresets.contains(preset)) {
      return null;
    }

    return preset;
  }
}
