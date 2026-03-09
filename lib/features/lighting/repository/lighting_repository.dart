import '../../../core/services/legion_frontend_bridge_service.dart';
import '../../../core/services/legion_sysfs_service.dart';
import '../models/lighting_snapshot.dart';

class LightingRepositoryException implements Exception {
  const LightingRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LightingRepository {
  const LightingRepository({
    required LegionSysfsService sysfsService,
    required LegionFrontendBridgeService bridgeService,
  }) : _sysfsService = sysfsService,
       _bridgeService = bridgeService;

  final LegionSysfsService _sysfsService;
  final LegionFrontendBridgeService _bridgeService;

  Future<LightingSnapshot> loadSnapshot() async {
    final whiteKeyboardBacklight = await _sysfsService
        .readWhiteKeyboardBacklightMode();
    final yLogoLight = await _sysfsService.readYLogoLightMode();
    final ioPortLight = await _sysfsService.readIoPortLightMode();

    return LightingSnapshot(
      whiteKeyboardBacklightEnabled: whiteKeyboardBacklight,
      whiteKeyboardBacklightSupported: whiteKeyboardBacklight != null,
      yLogoLightEnabled: yLogoLight,
      yLogoLightSupported: yLogoLight != null,
      ioPortLightEnabled: ioPortLight,
      ioPortLightSupported: ioPortLight != null,
    );
  }

  Future<void> setWhiteKeyboardBacklight(bool enabled) async {
    await _runFeatureToggle(
      featureName: 'WhiteKeyboardBacklightFeature', // legion_linux/legion.py:WhiteKeyboardBacklightFeature
      enabled: enabled,
      settingLabel: 'White keyboard backlight',
      detectUnavailableResponse: true,
    );
  }

  Future<void> setYLogoLight(bool enabled) async {
    await _runFeatureToggle(
      featureName: 'YLogoLight', // legion_linux/legion.py:YLogoLight
      enabled: enabled,
      settingLabel: 'Y-logo light',
      detectUnavailableResponse: true,
    );
  }

  Future<void> setIoPortLight(bool enabled) async {
    await _runFeatureToggle(
      featureName: 'IOPortLight', // legion_linux/legion.py:IOPortLight
      enabled: enabled,
      settingLabel: 'IO-port light',
      detectUnavailableResponse: true,
    );
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

      throw LightingRepositoryException(message);
    }
  }
}
