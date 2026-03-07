import '../../../core/services/legion_frontend_bridge_service.dart';
import '../../../core/services/legion_sysfs_service.dart';
import '../../../core/services/xrandr_service.dart';
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
    required XrandrService xrandrService,
  }) : _sysfsService = sysfsService,
       _bridgeService = bridgeService,
       _xrandrService = xrandrService;

  final LegionSysfsService _sysfsService;
  final LegionFrontendBridgeService _bridgeService;
  final XrandrService _xrandrService;

  Future<DisplayLightingSnapshot> loadSnapshot() async {
    final hybridMode = await _sysfsService.readHybridMode();
    final overdriveMode = await _sysfsService.readOverdriveMode();
    final whiteKeyboardBacklight = await _sysfsService
        .readWhiteKeyboardBacklightMode();
    final yLogoLight = await _sysfsService.readYLogoLightMode();
    final ioPortLight = await _sysfsService.readIoPortLightMode();
    final displayInfo = await _xrandrService.queryBuiltInDisplay();

    return DisplayLightingSnapshot(
      hybridModeEnabled: hybridMode,
      hybridModeSupported: hybridMode != null,
      overdriveEnabled: overdriveMode,
      overdriveSupported: overdriveMode != null,
      whiteKeyboardBacklightEnabled: whiteKeyboardBacklight,
      whiteKeyboardBacklightSupported: whiteKeyboardBacklight != null,
      yLogoLightEnabled: yLogoLight,
      yLogoLightSupported: yLogoLight != null,
      ioPortLightEnabled: ioPortLight,
      ioPortLightSupported: ioPortLight != null,
      xrandrOutputName: displayInfo?.outputName,
      availableRefreshRates: displayInfo?.availableRates,
      currentRefreshRate: displayInfo?.currentRate,
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
    await _runFeatureToggle(
      featureName: 'OverdriveFeature',
      enabled: enabled,
      settingLabel: 'Overdrive',
    );
  }

  Future<void> setWhiteKeyboardBacklight(bool enabled) async {
    await _runFeatureToggle(
      featureName: 'WhiteKeyboardBacklightFeature',
      enabled: enabled,
      settingLabel: 'White keyboard backlight',
      detectUnavailableResponse: true,
    );
  }

  Future<void> setYLogoLight(bool enabled) async {
    await _runFeatureToggle(
      featureName: 'YLogoLight',
      enabled: enabled,
      settingLabel: 'Y-logo light',
      detectUnavailableResponse: true,
    );
  }

  Future<void> setIoPortLight(bool enabled) async {
    await _runFeatureToggle(
      featureName: 'IOPortLight',
      enabled: enabled,
      settingLabel: 'IO-port light',
      detectUnavailableResponse: true,
    );
  }

  Future<void> setRefreshRate(String outputName, double rate) async {
    try {
      await _xrandrService.setRefreshRate(outputName, rate);
    } on XrandrServiceException catch (error) {
      throw DisplayLightingRepositoryException('$error');
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

      throw DisplayLightingRepositoryException(message);
    }
  }
}
