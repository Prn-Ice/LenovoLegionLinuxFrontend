import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/data/privileged_repository.dart';
import '../../../core/services/legion_sysfs_service.dart';
import '../models/automation_config.dart';
import '../models/automation_trigger_snapshot.dart';

class AutomationRepositoryException implements Exception {
  const AutomationRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AutomationRepository extends PrivilegedRepository {
  const AutomationRepository({
    required LegionSysfsService sysfsService,
    required super.bridgeService,
  }) : _sysfsService = sysfsService;

  @override
  Exception wrapBridgeError(String message) =>
      AutomationRepositoryException(message);

  final LegionSysfsService _sysfsService;

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
    await runPrivilegedCommand(
      ['fancurve-write-current-preset-to-hw'],
      method: 'fan_curve.apply_context_preset',
      failurePrefix: 'Failed to apply fan preset for current context',
    );
  }

  Future<void> applyCustomConservation({
    required int lowerLimit,
    required int upperLimit,
  }) async {
    await runPrivilegedCommand(
      ['custom-conservation-mode-apply', '$lowerLimit', '$upperLimit'],
      method: 'battery_conservation.custom_apply',
      failurePrefix: 'Failed to apply custom conservation automation',
    );
  }

  Future<void> setRapidChargingEnabled(bool enabled) async {
    final command = enabled
        ? 'rapid-charging-enable'
        : 'rapid-charging-disable';
    await runPrivilegedCommand(
      [command],
      method: 'rapid_charging.set',
      failurePrefix:
          'Failed to set rapid charging to ${enabled ? 'on' : 'off'} in automation',
    );
  }

  /// Runs [command] as the current user (NOT privileged — no pkexec).
  /// Returns the trimmed stdout on success.
  /// Throws [AutomationRepositoryException] on non-zero exit or timeout.
  Future<String> runShellCommand(String command) async {
    try {
      final result = await Process.run('sh', [
        '-c',
        command,
      ]).timeout(const Duration(seconds: 30));
      if (result.exitCode == 0) {
        return '${result.stdout}'.trim();
      }
      final stderr = '${result.stderr}'.trim();
      final detail = stderr.isNotEmpty ? ': $stderr' : '';
      throw AutomationRepositoryException(
        'External command exited with code ${result.exitCode}$detail',
      );
    } on TimeoutException {
      throw const AutomationRepositoryException(
        'External command timed out after 30 seconds.',
      );
    } on ProcessException catch (e) {
      throw AutomationRepositoryException(
        'Failed to start external command: ${e.message}',
      );
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
