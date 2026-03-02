import 'dart:convert';
import 'dart:io';

import '../../../core/services/legion_cli_service.dart';
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
    required LegionCliService cliService,
  }) : _sysfsService = sysfsService,
       _cliService = cliService;

  final LegionSysfsService _sysfsService;
  final LegionCliService _cliService;

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
    await _runPrivilegedCommand([
      'fancurve-write-current-preset-to-hw',
    ], failurePrefix: 'Failed to apply fan preset for current context');
  }

  Future<void> applyCustomConservation({
    required int lowerLimit,
    required int upperLimit,
  }) async {
    await _runPrivilegedCommand([
      'custom-conservation-mode-apply',
      '$lowerLimit',
      '$upperLimit',
    ], failurePrefix: 'Failed to apply custom conservation automation');
  }

  Future<void> _runPrivilegedCommand(
    List<String> args, {
    required String failurePrefix,
  }) async {
    final result = await _cliService.runCommand(args, privileged: true);

    if (result.ok) {
      return;
    }

    final stderr = result.stderr.trim();
    final stdout = result.stdout.trim();
    final details = [
      if (stderr.isNotEmpty) stderr,
      if (stdout.isNotEmpty) stdout,
    ].join('\n');

    final message = details.isEmpty
        ? '$failurePrefix.'
        : '$failurePrefix: $details';
    throw AutomationRepositoryException(message);
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
