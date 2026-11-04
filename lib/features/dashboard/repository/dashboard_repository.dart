import '../../../core/data/privileged_repository.dart';
import '../../../core/models/app_failure.dart';
import '../../../core/models/control_selectors.dart';
import '../../../core/services/legion_sysfs_service.dart';
import '../../../core/services/power_profile_service.dart';
import '../models/dashboard_snapshot.dart';
import '../models/device_identity_snapshot.dart';

class DashboardRepositoryException extends AppFailure {
  const DashboardRepositoryException(
    super.message, {
    super.kind,
    super.details,
  });
}

class DashboardRepository extends PrivilegedRepository {
  const DashboardRepository({
    required LegionSysfsService sysfsService,
    required PowerProfileService powerProfileService,
    required super.bridgeService,
  }) : _sysfsService = sysfsService,
       _powerProfileService = powerProfileService;

  @override
  Exception wrapBridgeError(AppFailure failure) => DashboardRepositoryException(
    failure.message,
    kind: failure.kind,
    details: failure.details,
  );

  final LegionSysfsService _sysfsService;
  final PowerProfileService _powerProfileService;

  static const List<String> _fallbackModeValues = [
    'quiet',
    'balanced',
    'performance',
    'balanced-performance',
  ];

  Future<DashboardSnapshot> loadSnapshot() async {
    final status = await _sysfsService.readSystemStatus();
    final choicesRaw = await _sysfsService.readPlatformProfileChoices();
    final hybridMode = await _sysfsService.readHybridMode();
    final overdriveMode = await _sysfsService.readOverdriveMode();
    final onPowerSupply = await _sysfsService.readOnPowerSupplyMode();
    final daemonSnapshot = await _powerProfileService.loadDaemonSnapshot();

    final hardwareProfiles = choicesRaw.isEmpty
        ? daemonSnapshot == null
              ? _fallbackModeValues
              : const <String>[]
        : choicesRaw;
    final values = <String>[];
    final source = _powerProfileService.availableProfiles(
      hardwareProfiles: hardwareProfiles,
      daemon: daemonSnapshot,
    );
    for (final raw in source) {
      final value = raw.trim();
      if (value.isNotEmpty && !values.contains(value)) {
        values.add(value);
      }
    }

    final current = status.powerProfile?.trim();
    if (current != null && current.isNotEmpty && !values.contains(current)) {
      values.insert(0, current);
    }

    final identity = await _loadDeviceIdentity();

    return DashboardSnapshot(
      status: status,
      availablePowerModes: values,
      hybridModeEnabled: hybridMode,
      overdriveEnabled: overdriveMode,
      onPowerSupply: onPowerSupply,
      recommendedFanPreset: _computeRecommendedPreset(
        profile: current,
        onPowerSupply: onPowerSupply,
      ),
      deviceIdentity: identity,
    );
  }

  Future<DeviceIdentitySnapshot> _loadDeviceIdentity() async {
    final results = await Future.wait([
      _sysfsService.readDeviceProductFamily(),
      _sysfsService.readDeviceProductName(),
      _sysfsService.readDeviceSerial(),
      _sysfsService.readBiosVersion(),
      _sysfsService.readCpuName(),
      _sysfsService.readKernelRelease(),
      _sysfsService.readLegionModuleVersion(),
    ]);
    final uptime = await _sysfsService.readUptimeSeconds();
    return DeviceIdentitySnapshot(
      productFamily: results[0],
      productName: results[1],
      serial: results[2],
      biosVersion: results[3],
      cpuName: results[4],
      kernelRelease: results[5],
      legionModuleVersion: results[6],
      uptimeSeconds: uptime,
    );
  }

  Future<void> setPowerMode(String mode) async {
    await _powerProfileService.setProfile(
      mode,
      writePlatformProfile: _setPlatformProfile,
    );
  }

  Future<void> _setPlatformProfile(String mode) async {
    await runControlOperation(
      (client) => client.setFeature(ControlFeature.platformProfile, mode),
      args: [ControlFeature.platformProfile.wireValue, mode],
      method: 'feature.set',
      failurePrefix: 'Failed to set power mode to "$mode"',
    );
  }

  Future<void> setHybridMode(bool enabled) async {
    await runControlOperation(
      (client) => client.setToggle(ControlToggle.hybridMode, enabled),
      args: ['$enabled'],
      method: 'hybrid_mode.set',
      failurePrefix: 'Failed to set Hybrid mode',
    );
  }

  Future<void> applyContextFanPreset() async {
    await runControlOperation(
      (client) => client.applyCurrentFanPreset(),
      method: 'fan_curve.apply_context_preset',
      failurePrefix: 'Failed to apply current context fan preset',
    );
  }

  Future<void> setOverdriveMode(bool enabled) async {
    await runControlOperation(
      (client) =>
          client.setFeature(ControlFeature.overdrive, enabled ? '1' : '0'),
      args: [ControlFeature.overdrive.wireValue, '$enabled'],
      method: 'feature.set',
      failurePrefix: 'Failed to set Overdrive to ${enabled ? 'on' : 'off'}',
    );
  }

  String? _computeRecommendedPreset({
    required String? profile,
    required bool? onPowerSupply,
  }) {
    if (profile == null || onPowerSupply == null) {
      return null;
    }

    final suffix = onPowerSupply ? 'ac' : 'battery';
    return '${profile.trim()}-$suffix';
  }
}
