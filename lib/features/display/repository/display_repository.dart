import '../../../core/services/legion_frontend_bridge_service.dart';
import '../../../core/services/legion_sysfs_service.dart';
import '../../../core/services/xrandr_service.dart';
import '../models/display_snapshot.dart';

class DisplayRepositoryException implements Exception {
  const DisplayRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DisplayRepository {
  const DisplayRepository({
    required LegionSysfsService sysfsService,
    required LegionFrontendBridgeService bridgeService,
    required XrandrService xrandrService,
  }) : _sysfsService = sysfsService,
       _bridgeService = bridgeService,
       _xrandrService = xrandrService;

  final LegionSysfsService _sysfsService;
  final LegionFrontendBridgeService _bridgeService;
  final XrandrService _xrandrService;

  Future<DisplaySnapshot> loadSnapshot() async {
    final overdriveMode = await _sysfsService.readOverdriveMode();
    final displayInfo = await _xrandrService.queryBuiltInDisplay();

    return DisplaySnapshot(
      overdriveEnabled: overdriveMode,
      overdriveSupported: overdriveMode != null,
      xrandrOutputName: displayInfo?.outputName,
      availableRefreshRates: displayInfo?.availableRates,
      currentRefreshRate: displayInfo?.currentRate,
    );
  }

  Future<void> setOverdriveMode(bool enabled) async {
    await _runFeatureToggle(
      featureName: 'OverdriveFeature', // legion_linux/legion.py:OverdriveFeature
      enabled: enabled,
      settingLabel: 'Overdrive',
    );
  }

  Future<void> setRefreshRate(String outputName, double rate) async {
    try {
      await _xrandrService.setRefreshRate(outputName, rate);
    } on XrandrServiceException catch (error) {
      throw DisplayRepositoryException('$error');
    }
  }

  Future<void> _runFeatureToggle({
    required String featureName,
    required bool enabled,
    required String settingLabel,
    bool detectUnavailableResponse = false,
  }) async {
    try {
      await _bridgeService.runPrivilegedCommand(
        method: 'feature.set',
        args: ['set-feature', featureName, enabled ? '1' : '0'],
        detectUnavailableResponse: detectUnavailableResponse,
      );
    } on LegionBridgeException catch (error) {
      final details = error.details;
      final message = details.isEmpty
          ? 'Failed to set $settingLabel to ${enabled ? 'on' : 'off'}.'
          : 'Failed to set $settingLabel: $details';

      throw DisplayRepositoryException(message);
    }
  }
}
