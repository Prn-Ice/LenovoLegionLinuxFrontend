import '../../../core/data/privileged_repository.dart';
import '../../../core/services/legion_sysfs_service.dart';
import '../models/lighting_snapshot.dart';

class LightingRepositoryException implements Exception {
  const LightingRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LightingRepository extends PrivilegedRepository {
  const LightingRepository({
    required LegionSysfsService sysfsService,
    required super.bridgeService,
  }) : _sysfsService = sysfsService;

  @override
  Exception wrapBridgeError(String message) =>
      LightingRepositoryException(message);

  final LegionSysfsService _sysfsService;

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
      featureName:
          'WhiteKeyboardBacklightFeature', // legion_linux/legion.py:WhiteKeyboardBacklightFeature
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
  }) => runPrivilegedCommand(
    ['set-feature', featureName, enabled ? '1' : '0'],
    method: 'feature.set',
    failurePrefix: 'Failed to set $settingLabel to ${enabled ? 'on' : 'off'}',
    detectUnavailableResponse: detectUnavailableResponse,
  );
}
