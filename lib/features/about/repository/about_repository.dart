import 'dart:io';

import '../../../core/models/hardware_check.dart';
import '../../../core/services/legion_cli_service.dart';
import '../../../core/services/legion_frontend_bridge_service.dart';
import '../../../core/services/legion_sysfs_service.dart';
import '../models/about_diagnostic_item.dart';
import '../models/about_snapshot.dart';

class AboutRepository {
  AboutRepository({
    required LegionSysfsService sysfs,
    required LegionCliService cli,
    required LegionFrontendBridgeService bridge,
    ProcessRunner? processRunner,
  }) : _sysfs = sysfs,
       _cli = cli,
       _bridge = bridge,
       _processRunner = processRunner ?? Process.run;

  final LegionSysfsService _sysfs;
  final LegionCliService _cli;
  final LegionFrontendBridgeService _bridge;
  final ProcessRunner _processRunner;

  Future<AboutSnapshot> loadSnapshot() async {
    final results = await _sysfs.readHardwareProbes();
    final probes = results.checks;
    final diagnostics = <AboutDiagnosticItem>[
      for (final entry in probes.entries)
        AboutDiagnosticItem.fromProbe(
          id: entry.key.jsonId,
          label: entry.key.label,
          probe: entry.value,
          frontendWriteAvailable: entry.key.writable,
        ),
      for (var index = 0; index < results.sensorProviders.length; index++)
        AboutDiagnosticItem.fromProbe(
          id: 'hwmon_provider_${index + 1}',
          label: 'Sensor provider ${index + 1}',
          probe: results.sensorProviders[index],
          frontendWriteAvailable: false,
        ),
    ];
    final family = probes[HardwareCheck.productFamily]?.selectedRead?.value;
    final name = probes[HardwareCheck.productName]?.selectedRead?.value;
    final hardwareModel = family == null
        ? name
        : name == null
        ? family
        : '$family ($name)';
    final cliPathExists = File(_cli.cliPath).existsSync();
    final pythonAvailable = await _isCommandAvailable('python3');
    final controlServiceActive = await _isControlServiceActive();
    final systemctlAvailable = await _isCommandAvailable('systemctl');
    final cliProbe = await _probeCliHealth();
    final cliVersion = await _readCliVersion();

    return AboutSnapshot(
      updatedAt: DateTime.now(),
      cliPath: _cli.cliPath,
      cliPathExists: cliPathExists,
      pythonAvailable: pythonAvailable,
      controlServiceActive: controlServiceActive,
      systemctlAvailable: systemctlAvailable,
      cliHealthy: cliProbe.$1,
      cliHealthSummary: cliProbe.$2,
      diagnostics: List.unmodifiable(diagnostics),
      kernelVersion: probes[HardwareCheck.kernelVersion]?.selectedRead?.value,
      hardwareModel: hardwareModel,
      biosVersion: probes[HardwareCheck.biosVersion]?.selectedRead?.value,
      moduleVersion: probes[HardwareCheck.moduleVersion]?.selectedRead?.value,
      cliVersion: cliVersion,
      commandHistory: _bridge.commandHistory,
    );
  }

  Future<(bool, String)> _probeCliHealth() async {
    try {
      final result = await _bridge.runCommand(
        method: 'diagnostics.cli_health',
        args: const ['--help'],
        timeout: const Duration(seconds: 2),
      );
      if (result.ok) return (true, 'Healthy');
      final output = _compactText(result.stderr);
      if (output.isNotEmpty) return (false, 'CLI error: $output');
      return (false, 'CLI exited with ${result.exitCode}');
    } on LegionBridgeException catch (error) {
      if (error.code == LegionBridgeErrorCode.timeout) {
        return (false, 'Timed out while probing CLI');
      }
      return (false, _compactText(error.toString()));
    } on ProcessException catch (error) {
      return (false, 'Process error: ${error.message}');
    } catch (error) {
      return (false, '$error');
    }
  }

  Future<String?> _readCliVersion() async {
    try {
      final result = await _bridge.runCommand(
        method: 'diagnostics.cli_version',
        args: const ['--version'],
        timeout: const Duration(seconds: 2),
      );
      if (!result.ok) return null;
      final lines = result.stdout
          .toString()
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty);
      if (lines.isEmpty) return null;
      // CLI output is external text; omit paths and long/unexpected output.
      final version = lines.first;
      return version.length <= 120 && !version.contains('/') ? version : null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _isCommandAvailable(String command) async {
    try {
      final result = await _processRunner('which', [command]);
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  Future<bool> _isControlServiceActive() async {
    try {
      final result = await _processRunner('systemctl', [
        'is-active',
        '--quiet',
        'legion-control.service',
      ]).timeout(const Duration(seconds: 2));
      return result.exitCode == 0;
    } on Object {
      return false;
    }
  }

  String _compactText(Object value) {
    final text = '$value'.trim();
    return text.length <= 120 ? text : '${text.substring(0, 117)}...';
  }
}
