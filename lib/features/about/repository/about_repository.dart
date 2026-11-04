import 'dart:io';

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
    final probes = await _sysfs.readHardwareProbes();
    final diagnostics = <AboutDiagnosticItem>[
      for (final entry in _probeLabels.entries)
        if (probes[entry.key] case final probe?)
          AboutDiagnosticItem.fromProbe(
            id: entry.key,
            label: entry.value,
            probe: probe,
            frontendWriteAvailable: _writeControls.contains(entry.key),
          ),
      for (final entry in probes.entries)
        if (entry.key.startsWith('hwmon_provider_'))
          AboutDiagnosticItem.fromProbe(
            id: entry.key,
            label: 'Sensor provider ${entry.key.split('_').last}',
            probe: entry.value,
            frontendWriteAvailable: false,
          ),
    ];
    final family = probes['product_family']?.selectedRead?.value;
    final name = probes['product_name']?.selectedRead?.value;
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
      kernelVersion: probes['kernel_version']?.selectedRead?.value,
      hardwareModel: hardwareModel,
      biosVersion: probes['bios_version']?.selectedRead?.value,
      moduleVersion: probes['module_version']?.selectedRead?.value,
      cliVersion: cliVersion,
      commandHistory: _bridge.commandHistory,
    );
  }

  static const _probeLabels = {
    'product_family': 'Model family',
    'product_name': 'Model identifier',
    'bios_version': 'BIOS version',
    'kernel_version': 'Kernel version',
    'module_version': 'Module version',
    'platform_profile': 'Platform profile',
    'platform_profile_choices': 'Platform profile choices',
    'hybrid_mode': 'Hybrid/G-Sync state',
    'overdrive': 'Overdrive state',
    'battery_conservation': 'Battery conservation',
    'rapid_charge': 'Rapid charging',
    'always_on_usb': 'Always-on USB charging',
    'touchpad': 'Touchpad state',
    'win_key': 'Win key lock',
    'camera_power': 'Camera power state',
    'fn_lock': 'Fn lock',
    'keyboard_backlight': 'Keyboard brightness',
    'y_logo': 'Y-logo brightness',
    'io_port_light': 'I/O-port brightness',
    'ac_online': 'AC adapter online',
    'lock_fan_controller': 'Fan controller lock',
    'fan_fullspeed': 'Max fan speed toggle',
    'mini_fan_curve': 'Mini fan curve mode',
    'fan1_rpm': 'Fan 1 (RPM)',
    'fan2_rpm': 'Fan 2 (RPM)',
    'fan1_provider': 'Fan 1 provider',
    'fan2_provider': 'Fan 2 provider',
    'hwmon_discovery': 'Sensor discovery',
    'ideapad_discovery': 'Ideapad discovery',
    'led_discovery': 'LED discovery',
  };

  // Settings the app can ask to change. The driver may still reject a change.
  static const _writeControls = {
    'platform_profile',
    'hybrid_mode',
    'overdrive',
    'battery_conservation',
    'rapid_charge',
    'always_on_usb',
    'touchpad',
    'win_key',
    'camera_power',
    'fn_lock',
    'keyboard_backlight',
    'y_logo',
    'io_port_light',
    'lock_fan_controller',
    'fan_fullspeed',
    'mini_fan_curve',
  };

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
