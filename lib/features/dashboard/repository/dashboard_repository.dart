import '../../../core/services/legion_frontend_bridge_service.dart';
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
    required LegionFrontendBridgeService bridgeService,
  }) : _sysfsService = sysfsService,
       _bridgeService = bridgeService;

  final LegionSysfsService _sysfsService;
  final LegionFrontendBridgeService _bridgeService;

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
    await _runPrivilegedCommand(
      ['set-feature', 'PlatformProfileFeature', mode],
      method: 'feature.set',
      failurePrefix: 'Failed to set power mode to "$mode"',
    );
  }

  Future<void> setHybridMode(bool enabled) async {
    final command = enabled ? 'hybrid-mode-enable' : 'hybrid-mode-disable';
    await _runPrivilegedCommand(
      [command],
      method: 'hybrid_mode.set',
      failurePrefix: 'Failed to set Hybrid mode',
      detectUnavailableResponse: true,
    );
  }

  Future<void> applyContextFanPreset() async {
    await _runPrivilegedCommand(
      const ['fancurve-write-current-preset-to-hw'],
      method: 'fan_curve.apply_context_preset',
      failurePrefix: 'Failed to apply current context fan preset',
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
    return '${profile.trim()}-$suffix';
  }

  Future<void> _runPrivilegedCommand(
    List<String> args, {
    required String method,
    required String failurePrefix,
    bool detectUnavailableResponse = false,
  }) async {
    try {
      await _bridgeService.runPrivilegedCommand(
        method: method,
        args: args,
        detectUnavailableResponse: detectUnavailableResponse,
      );
    } on LegionBridgeException catch (error) {
      final details = error.details;
      final message = details.isEmpty
          ? '$failurePrefix.'
          : '$failurePrefix: $details';
      throw DashboardRepositoryException(message);
    }
  }
}
