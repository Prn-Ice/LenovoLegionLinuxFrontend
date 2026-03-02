import '../../../core/services/legion_cli_service.dart';
import '../../../core/services/legion_sysfs_service.dart';
import '../models/dashboard_snapshot.dart';

class DashboardRepositoryException implements Exception {
  const DashboardRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DashboardRepository {
  const DashboardRepository({
    required LegionSysfsService sysfsService,
    required LegionCliService cliService,
  }) : _sysfsService = sysfsService,
       _cliService = cliService;

  final LegionSysfsService _sysfsService;
  final LegionCliService _cliService;

  static const List<String> _fallbackModeValues = [
    'quiet',
    'balanced',
    'performance',
    'balanced-performance',
  ];

  Future<DashboardSnapshot> loadSnapshot() async {
    final status = await _sysfsService.readSystemStatus();
    final choicesRaw = await _sysfsService.readPlatformProfileChoices();
    final hybridMode = await _sysfsService.readHybridMode();
    final onPowerSupply = await _sysfsService.readOnPowerSupplyMode();

    final values = <String>[];
    final source = choicesRaw.isEmpty ? _fallbackModeValues : choicesRaw;
    for (final raw in source) {
      final value = raw.trim();
      if (value.isNotEmpty && !values.contains(value)) {
        values.add(value);
      }
    }

    final current = status.powerProfile?.trim();
    if (current != null && current.isNotEmpty && !values.contains(current)) {
      values.insert(0, current);
    }

    return DashboardSnapshot(
      status: status,
      availablePowerModes: values,
      hybridModeEnabled: hybridMode,
      onPowerSupply: onPowerSupply,
      recommendedFanPreset: _computeRecommendedPreset(
        profile: current,
        onPowerSupply: onPowerSupply,
      ),
    );
  }

  Future<void> setPowerMode(String mode) async {
    await _runPrivilegedCommand([
      'set-feature',
      'PlatformProfileFeature',
      mode,
    ], failurePrefix: 'Failed to set power mode to "$mode"');
  }

  Future<void> setHybridMode(bool enabled) async {
    final command = enabled ? 'hybrid-mode-enable' : 'hybrid-mode-disable';
    final result = await _cliService.runCommand([command], privileged: true);

    final combinedLower = '${result.stdout}\n${result.stderr}'.toLowerCase();
    final likelyUnavailable = combinedLower.contains('command not available');

    if (result.exitCode == 0 && !likelyUnavailable) {
      return;
    }

    final details = _formatCommandDetails(result.stdout, result.stderr);
    final message = details.isEmpty
        ? 'Failed to set Hybrid mode.'
        : 'Failed to set Hybrid mode: $details';
    throw DashboardRepositoryException(message);
  }

  Future<void> applyContextFanPreset() async {
    await _runPrivilegedCommand(const [
      'fancurve-write-current-preset-to-hw',
    ], failurePrefix: 'Failed to apply current context fan preset');
  }

  String? _computeRecommendedPreset({
    required String? profile,
    required bool? onPowerSupply,
  }) {
    if (profile == null || onPowerSupply == null) {
      return null;
    }

    final suffix = onPowerSupply ? 'ac' : 'battery';
    return '${profile.trim()}-$suffix';
  }

  Future<void> _runPrivilegedCommand(
    List<String> args, {
    required String failurePrefix,
  }) async {
    final result = await _cliService.runCommand(args, privileged: true);
    if (result.ok) {
      return;
    }

    final details = _formatCommandDetails(result.stdout, result.stderr);
    final message = details.isEmpty
        ? '$failurePrefix.'
        : '$failurePrefix: $details';
    throw DashboardRepositoryException(message);
  }

  String _formatCommandDetails(String stdout, String stderr) {
    final out = stdout.trim();
    final err = stderr.trim();
    return [if (err.isNotEmpty) err, if (out.isNotEmpty) out].join('\n');
  }
}
