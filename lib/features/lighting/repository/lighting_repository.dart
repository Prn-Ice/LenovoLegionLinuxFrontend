import '../../../core/data/privileged_repository.dart';
import '../../../core/models/app_failure.dart';
import '../../../core/models/control_selectors.dart';
import '../../../core/services/legion_sysfs_service.dart';
import '../models/lighting_snapshot.dart';

class LightingRepositoryException extends AppFailure {
  const LightingRepositoryException(super.message, {super.kind, super.details});
}

class LightingRepository extends PrivilegedRepository {
  const LightingRepository({
    required LegionSysfsService sysfsService,
    required super.bridgeService,
  }) : _sysfsService = sysfsService;

  @override
  Exception wrapBridgeError(AppFailure failure) => LightingRepositoryException(
    failure.message,
    kind: failure.kind,
    details: failure.details,
  );

  final LegionSysfsService _sysfsService;

  Future<LightingSnapshot> loadSnapshot() async {
    final whiteKeyboardBacklight = await _sysfsService
        .readWhiteKeyboardBacklightMode();
    final yLogoLight = await _sysfsService.readYLogoLightMode();
    final ioPortLight = await _sysfsService.readIoPortLightMode();

    return LightingSnapshot(
      whiteKeyboardBacklightEnabled: whiteKeyboardBacklight,
      whiteKeyboardBacklightSupported: whiteKeyboardBacklight != null,
      whiteKeyboardBacklightWriteSupported: false,
      yLogoLightEnabled: yLogoLight,
      yLogoLightSupported: yLogoLight != null,
      ioPortLightEnabled: ioPortLight,
      ioPortLightSupported: ioPortLight != null,
    );
  }

  Future<void> setWhiteKeyboardBacklight(bool enabled) async {
    throw const LightingRepositoryException(
      'White keyboard backlight control is not supported by the control service.',
      kind: AppFailureKind.unavailable,
    );
  }

  Future<void> setYLogoLight(bool enabled) async {
    await _runFeatureToggle(
      feature: ControlFeature.yLogoLight,
      enabled: enabled,
      settingLabel: 'Y-logo light',
    );
  }

  Future<void> setIoPortLight(bool enabled) async {
    await _runFeatureToggle(
      feature: ControlFeature.ioPortLight,
      enabled: enabled,
      settingLabel: 'IO-port light',
    );
  }

  Future<void> _runFeatureToggle({
    required ControlFeature feature,
    required bool enabled,
    required String settingLabel,
  }) => runControlOperation(
    (client) => client.setFeature(feature, enabled ? '1' : '0'),
    args: [feature.wireValue, '$enabled'],
    method: 'feature.set',
    failurePrefix: 'Failed to set $settingLabel to ${enabled ? 'on' : 'off'}',
  );
}
