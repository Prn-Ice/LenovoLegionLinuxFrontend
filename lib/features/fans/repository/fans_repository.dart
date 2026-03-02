import '../../../core/services/legion_cli_service.dart';
import '../../../core/services/legion_sysfs_service.dart';
import '../models/fans_snapshot.dart';

class FansRepositoryException implements Exception {
  const FansRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FansRepository {
  const FansRepository({
    required LegionSysfsService sysfsService,
    required LegionCliService cliService,
  }) : _sysfsService = sysfsService,
       _cliService = cliService;

  final LegionSysfsService _sysfsService;
  final LegionCliService _cliService;

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

    return FansSnapshot(
      platformProfile: profile,
      onPowerSupply: onPowerSupply,
      recommendedPreset: recommendedPreset,
      availablePresets: defaultPresets,
      miniFanCurveEnabled: miniFanCurve,
      lockFanControllerEnabled: lockFanController,
      maximumFanSpeedEnabled: maximumFanSpeed,
    );
  }

  Future<void> applyCurrentContextPreset() async {
    await _runPrivilegedCommand([
      'fancurve-write-current-preset-to-hw',
    ], failurePrefix: 'Failed to apply current context fan preset');
  }

  Future<void> applyPreset(String presetName) async {
    await _runPrivilegedCommand([
      'fancurve-write-preset-to-hw',
      presetName,
    ], failurePrefix: 'Failed to apply fan preset "$presetName"');
  }

  Future<void> setMiniFanCurve(bool enabled) async {
    final command = enabled ? 'minifancurve-enable' : 'minifancurve-disable';
    await _runPrivilegedCommand(
      [command],
      failurePrefix:
          'Failed to set mini fan curve to ${enabled ? 'on' : 'off'}',
    );
  }

  Future<void> setLockFanController(bool enabled) async {
    final command = enabled
        ? 'lockfancontroller-enable'
        : 'lockfancontroller-disable';
    await _runPrivilegedCommand(
      [command],
      failurePrefix:
          'Failed to set lock fan controller to ${enabled ? 'on' : 'off'}',
    );
  }

  Future<void> setMaximumFanSpeed(bool enabled) async {
    final command = enabled
        ? 'maximumfanspeed-enable'
        : 'maximumfanspeed-disable';
    await _runPrivilegedCommand(
      [command],
      failurePrefix:
          'Failed to set maximum fan speed to ${enabled ? 'on' : 'off'}',
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

  Future<void> _runPrivilegedCommand(
    List<String> args, {
    required String failurePrefix,
  }) async {
    final result = await _cliService.runCommand(args, privileged: true);

    final stderr = result.stderr.trim();
    final stdout = result.stdout.trim();

    if (result.ok) {
      return;
    }

    final details = [
      if (stderr.isNotEmpty) stderr,
      if (stdout.isNotEmpty) stdout,
    ].join('\n');

    final message = details.isEmpty
        ? '$failurePrefix.'
        : '$failurePrefix: $details';
    throw FansRepositoryException(message);
  }
}
