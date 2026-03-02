import '../../../core/services/legion_frontend_bridge_service.dart';
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
    required LegionFrontendBridgeService bridgeService,
  }) : _sysfsService = sysfsService,
       _bridgeService = bridgeService;

  final LegionSysfsService _sysfsService;
  final LegionFrontendBridgeService _bridgeService;

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
    try {
      await _bridgeService.runPrivilegedCommand(
        method: 'hybrid_mode.set',
        args: [command],
        detectUnavailableResponse: true,
      );
    } on LegionBridgeException catch (error) {
      final details = error.details;
      final message = details.isEmpty
          ? 'Failed to set Hybrid mode to ${enabled ? 'on' : 'off'}.'
          : 'Failed to set Hybrid mode: $details';

      throw DisplayLightingRepositoryException(message);
    }
  }

  Future<void> setOverdriveMode(bool enabled) async {
    try {
      await _bridgeService.runPrivilegedCommand(
        method: 'feature.set',
        args: ['set-feature', 'OverdriveFeature', enabled ? '1' : '0'],
      );
    } on LegionBridgeException catch (error) {
      final details = error.details;
      final message = details.isEmpty
          ? 'Failed to set Overdrive to ${enabled ? 'on' : 'off'}.'
          : 'Failed to set Overdrive: $details';

      throw DisplayLightingRepositoryException(message);
    }
  }
}
