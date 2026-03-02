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
  }) : _sysfs = sysfs,
       _cli = cli,
       _bridge = bridge;

  final LegionSysfsService _sysfs;
  final LegionCliService _cli;
  final LegionFrontendBridgeService _bridge;

  Future<AboutSnapshot> loadSnapshot() async {
    final diagnostics = <AboutDiagnosticItem>[];

    diagnostics.add(await _probePlatformProfile());
    diagnostics.add(
      await _probeBoolFeature(
        id: 'hybrid_mode',
        label: 'Hybrid/G-Sync state',
        reader: _sysfs.readHybridMode,
      ),
    );
    diagnostics.add(
      await _probeBoolFeature(
        id: 'overdrive',
        label: 'Overdrive state',
        reader: _sysfs.readOverdriveMode,
      ),
    );
    diagnostics.add(
      await _probeBoolFeature(
        id: 'battery_conservation',
        label: 'Battery conservation',
        reader: _sysfs.readBatteryConservationMode,
      ),
    );
    diagnostics.add(
      await _probeBoolFeature(
        id: 'rapid_charge',
        label: 'Rapid charging',
        reader: _sysfs.readRapidChargingMode,
      ),
    );
    diagnostics.add(
      await _probeBoolFeature(
        id: 'always_on_usb',
        label: 'Always-on USB charging',
        reader: _sysfs.readAlwaysOnUsbChargingMode,
      ),
    );
    diagnostics.add(
      await _probeBoolFeature(
        id: 'touchpad',
        label: 'Touchpad state',
        reader: _sysfs.readTouchpadMode,
      ),
    );
    diagnostics.add(
      await _probeBoolFeature(
        id: 'win_key',
        label: 'Win key lock',
        reader: _sysfs.readWinKeyMode,
      ),
    );
    diagnostics.add(
      await _probeBoolFeature(
        id: 'camera_power',
        label: 'Camera power state',
        reader: _sysfs.readCameraPowerMode,
      ),
    );
    diagnostics.add(
      await _probeBoolFeature(
        id: 'ac_online',
        label: 'AC adapter online',
        reader: _sysfs.readOnPowerSupplyMode,
      ),
    );
    diagnostics.add(
      await _probeBoolFeature(
        id: 'lock_fan_controller',
        label: 'Fan controller lock',
        reader: _sysfs.readLockFanControllerMode,
      ),
    );
    diagnostics.add(
      await _probeBoolFeature(
        id: 'fan_fullspeed',
        label: 'Max fan speed toggle',
        reader: _sysfs.readMaximumFanSpeedMode,
      ),
    );
    diagnostics.add(
      await _probeBoolFeature(
        id: 'mini_fan_curve',
        label: 'Mini fan curve mode',
        reader: _sysfs.readMiniFanCurveMode,
      ),
    );

    final cliPathExists = File(_cli.cliPath).existsSync();
    final pythonAvailable = await _isCommandAvailable('python3');
    final pkexecAvailable = await _isCommandAvailable('pkexec');
    final systemctlAvailable = await _isCommandAvailable('systemctl');
    final cliProbe = await _probeCliHealth();

    return AboutSnapshot(
      updatedAt: DateTime.now(),
      cliPath: _cli.cliPath,
      cliPathExists: cliPathExists,
      pythonAvailable: pythonAvailable,
      pkexecAvailable: pkexecAvailable,
      systemctlAvailable: systemctlAvailable,
      cliHealthy: cliProbe.$1,
      cliHealthSummary: cliProbe.$2,
      diagnostics: diagnostics,
    );
  }

  Future<AboutDiagnosticItem> _probePlatformProfile() async {
    try {
      final profile = await _sysfs.readPlatformProfile();
      final choices = await _sysfs.readPlatformProfileChoices();
      if (profile == null) {
        return const AboutDiagnosticItem(
          id: 'platform_profile',
          label: 'Platform profile',
          status: AboutDiagnosticStatus.unavailable,
          value: 'Unavailable',
          details: 'Missing /sys/firmware/acpi/platform_profile',
        );
      }

      final details = choices.isEmpty ? null : 'choices: ${choices.join(', ')}';
      return AboutDiagnosticItem(
        id: 'platform_profile',
        label: 'Platform profile',
        status: AboutDiagnosticStatus.ok,
        value: profile,
        details: details,
      );
    } catch (error) {
      return AboutDiagnosticItem(
        id: 'platform_profile',
        label: 'Platform profile',
        status: AboutDiagnosticStatus.error,
        value: 'Read error',
        details: '$error',
      );
    }
  }

  Future<AboutDiagnosticItem> _probeBoolFeature({
    required String id,
    required String label,
    required Future<bool?> Function() reader,
  }) async {
    try {
      final value = await reader();
      if (value == null) {
        return AboutDiagnosticItem(
          id: id,
          label: label,
          status: AboutDiagnosticStatus.unavailable,
          value: 'Unavailable',
          details: 'No readable sysfs node for this capability.',
        );
      }

      return AboutDiagnosticItem(
        id: id,
        label: label,
        status: AboutDiagnosticStatus.ok,
        value: value ? 'Enabled' : 'Disabled',
      );
    } catch (error) {
      return AboutDiagnosticItem(
        id: id,
        label: label,
        status: AboutDiagnosticStatus.error,
        value: 'Read error',
        details: '$error',
      );
    }
  }

  Future<(bool, String)> _probeCliHealth() async {
    try {
      final result = await _bridge.runCommand(
        method: 'diagnostics.cli_health',
        args: const ['--help'],
        timeout: const Duration(seconds: 2),
      );
      if (result.ok) {
        return (true, 'Healthy');
      }

      final output = _compactText(result.stderr);
      if (output.isNotEmpty) {
        return (false, 'CLI error: $output');
      }

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

  Future<bool> _isCommandAvailable(String command) async {
    try {
      final result = await Process.run('which', [command]);
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  String _compactText(Object value) {
    final text = '$value'.trim();
    if (text.length <= 120) {
      return text;
    }
    return '${text.substring(0, 117)}...';
  }
}
