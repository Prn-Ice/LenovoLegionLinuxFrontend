import 'dart:convert';
import 'dart:io';

import '../../../core/services/legion_frontend_bridge_service.dart';
import '../../../core/services/legion_sysfs_service.dart';
import '../models/automation_config.dart';
import '../models/automation_trigger_snapshot.dart';

class AutomationRepositoryException implements Exception {
  const AutomationRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AutomationRepository {
  const AutomationRepository({
    required LegionSysfsService sysfsService,
    required LegionFrontendBridgeService bridgeService,
  }) : _sysfsService = sysfsService,
       _bridgeService = bridgeService;

  final LegionSysfsService _sysfsService;
  final LegionFrontendBridgeService _bridgeService;

  Future<AutomationConfig> loadConfig() async {
    final file = _configFile;
    if (!await file.exists()) {
      return AutomationConfig.defaults();
    }

    try {
      final raw = await file.readAsString();
      final parsed = jsonDecode(raw);
      if (parsed is Map<String, dynamic>) {
        return AutomationConfig.fromJson(parsed);
      }
      if (parsed is Map) {
        return AutomationConfig.fromJson(parsed.cast<String, dynamic>());
      }
      return AutomationConfig.defaults();
    } catch (_) {
      return AutomationConfig.defaults();
    }
  }

  Future<void> saveConfig(AutomationConfig config) async {
    final file = _configFile;
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(config.toJson()),
    );
  }

  Future<AutomationTriggerSnapshot> readTriggerSnapshot() async {
    final profile = await _sysfsService.readPlatformProfile();
    final onSupply = await _sysfsService.readOnPowerSupplyMode();

    return AutomationTriggerSnapshot(
      platformProfile: profile,
      onPowerSupply: onSupply,
    );
  }

  Future<void> applyFanPresetForCurrentContext() async {
    await _runPrivilegedCommand(
      ['fancurve-write-current-preset-to-hw'],
      method: 'fan_curve.apply_context_preset',
      failurePrefix: 'Failed to apply fan preset for current context',
    );
  }

  Future<void> applyCustomConservation({
    required int lowerLimit,
    required int upperLimit,
  }) async {
    await _runPrivilegedCommand(
      ['custom-conservation-mode-apply', '$lowerLimit', '$upperLimit'],
      method: 'battery_conservation.custom_apply',
      failurePrefix: 'Failed to apply custom conservation automation',
    );
  }

  Future<void> setRapidChargingEnabled(bool enabled) async {
    final command = enabled
        ? 'rapid-charging-enable'
        : 'rapid-charging-disable';
    await _runPrivilegedCommand(
      [command],
      method: 'rapid_charging.set',
      failurePrefix:
          'Failed to set rapid charging to ${enabled ? 'on' : 'off'} in automation',
    );
  }

  Future<void> _runPrivilegedCommand(
    List<String> args, {
    required String method,
    required String failurePrefix,
  }) async {
    try {
      await _bridgeService.runPrivilegedCommand(method: method, args: args);
    } on LegionBridgeException catch (error) {
      final details = error.details;
      final message = details.isEmpty
          ? '$failurePrefix.'
          : '$failurePrefix: $details';
      throw AutomationRepositoryException(message);
    }
  }

  File get _configFile {
    final home = Platform.environment['HOME'];
    final baseDir = home != null && home.isNotEmpty
        ? Directory(home)
        : Directory('/tmp');
    return File(
      '${baseDir.path}/.config/legion_frontend/automation_rules.json',
    );
  }
}
