import '../../../core/services/legion_cli_service.dart';
import '../../../core/services/legion_sysfs_service.dart';
import '../models/display_lighting_snapshot.dart';

class DisplayLightingRepositoryException implements Exception {
  const DisplayLightingRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DisplayLightingRepository {
  const DisplayLightingRepository({
    required LegionSysfsService sysfsService,
    required LegionCliService cliService,
  }) : _sysfsService = sysfsService,
       _cliService = cliService;

  final LegionSysfsService _sysfsService;
  final LegionCliService _cliService;

  Future<DisplayLightingSnapshot> loadSnapshot() async {
    final hybridMode = await _sysfsService.readHybridMode();
    final overdriveMode = await _sysfsService.readOverdriveMode();

    return DisplayLightingSnapshot(
      hybridModeEnabled: hybridMode,
      hybridModeSupported: hybridMode != null,
      overdriveEnabled: overdriveMode,
      overdriveSupported: overdriveMode != null,
    );
  }

  Future<void> setHybridMode(bool enabled) async {
    final command = enabled ? 'hybrid-mode-enable' : 'hybrid-mode-disable';
    final result = await _cliService.runCommand([command], privileged: true);

    final combinedLower = '${result.stdout}\n${result.stderr}'.toLowerCase();
    final likelyUnavailable = combinedLower.contains('command not available');

    if (result.exitCode == 0 && !likelyUnavailable) {
      return;
    }

    final stderr = result.stderr.trim();
    final stdout = result.stdout.trim();

    final details = [
      if (stderr.isNotEmpty) stderr,
      if (stdout.isNotEmpty) stdout,
    ].join('\n');

    final message = details.isEmpty
        ? 'Failed to set Hybrid mode to ${enabled ? 'on' : 'off'}.'
        : 'Failed to set Hybrid mode: $details';

    throw DisplayLightingRepositoryException(message);
  }

  Future<void> setOverdriveMode(bool enabled) async {
    final result = await _cliService.runCommand([
      'set-feature',
      'OverdriveFeature',
      enabled ? '1' : '0',
    ], privileged: true);

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
        ? 'Failed to set Overdrive to ${enabled ? 'on' : 'off'}.'
        : 'Failed to set Overdrive: $details';

    throw DisplayLightingRepositoryException(message);
  }
}
