import 'dart:convert';

import '../../../core/data/privileged_repository.dart';
import '../../../core/models/app_failure.dart';
import '../../../core/models/control_selectors.dart';
import '../../../core/services/legion_sysfs_service.dart';
import '../models/fan_curve.dart';
import '../models/fans_snapshot.dart';

class FansRepositoryException extends AppFailure {
  const FansRepositoryException(super.message, {super.kind, super.details});
}

class FansRepository extends PrivilegedRepository {
  const FansRepository({
    required LegionSysfsService sysfsService,
    required super.bridgeService,
  }) : _sysfsService = sysfsService;

  @override
  Exception wrapBridgeError(AppFailure failure) => FansRepositoryException(
    failure.message,
    kind: failure.kind,
    details: failure.details,
  );

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
    await runControlOperation(
      (client) => client.applyCurrentFanPreset(),
      method: 'fan_curve.apply_context_preset',
      failurePrefix: 'Failed to apply current context fan preset',
    );
  }

  Future<void> applyPreset(String presetName) async {
    await runControlOperation(
      (client) => client.applyFanPreset(ControlFanPreset.parse(presetName)),
      args: [presetName],
      method: 'fan_curve.apply_preset',
      failurePrefix: 'Failed to apply fan preset "$presetName"',
    );
  }

  Future<void> setMiniFanCurve(bool enabled) async {
    await runControlOperation(
      (client) => client.setToggle(ControlToggle.miniFanCurve, enabled),
      args: ['$enabled'],
      method: 'mini_fan_curve.set',
      failurePrefix:
          'Failed to set mini fan curve to ${enabled ? 'on' : 'off'}',
    );
  }

  Future<void> setLockFanController(bool enabled) async {
    await runControlOperation(
      (client) => client.setToggle(ControlToggle.lockFanController, enabled),
      args: ['$enabled'],
      method: 'lock_fan_controller.set',
      failurePrefix:
          'Failed to set lock fan controller to ${enabled ? 'on' : 'off'}',
    );
  }

  Future<void> setMaximumFanSpeed(bool enabled) async {
    await runControlOperation(
      (client) => client.setToggle(ControlToggle.maximumFanSpeed, enabled),
      args: ['$enabled'],
      method: 'maximum_fan_speed.set',
      failurePrefix:
          'Failed to set maximum fan speed to ${enabled ? 'on' : 'off'}',
    );
  }

  Future<void> writeFanCurveToHardware(FanCurve curve) async {
    final bytes = utf8.encode(curve.toYaml());
    await runControlOperation(
      (client) => client.applyFanCurve(bytes),
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
