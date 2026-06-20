import '../../../core/data/privileged_repository.dart';
import '../../../core/services/legion_sysfs_service.dart';
import '../../../core/services/xrandr_service.dart';
import '../models/display_snapshot.dart';

class DisplayRepositoryException implements Exception {
  const DisplayRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DisplayRepository extends PrivilegedRepository {
  const DisplayRepository({
    required LegionSysfsService sysfsService,
    required super.bridgeService,
    required XrandrService xrandrService,
  }) : _sysfsService = sysfsService,
       _xrandrService = xrandrService;

  @override
  Exception wrapBridgeError(String message) =>
      DisplayRepositoryException(message);

  final LegionSysfsService _sysfsService;
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
      featureName:
          'OverdriveFeature', // legion_linux/legion.py:OverdriveFeature
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
  }) => runPrivilegedCommand(
    ['set-feature', featureName, enabled ? '1' : '0'],
    method: 'feature.set',
    failurePrefix: 'Failed to set $settingLabel to ${enabled ? 'on' : 'off'}',
    detectUnavailableResponse: detectUnavailableResponse,
  );
}
