import '../../../core/data/privileged_repository.dart';
import '../../../core/models/app_failure.dart';
import '../../../core/models/control_selectors.dart';
import '../../../core/services/legion_sysfs_service.dart';
import '../../../core/services/power_profile_service.dart';
import '../models/power_limit.dart';
import '../models/power_mode.dart';
import '../models/power_model_defaults.dart';
import '../models/power_snapshot.dart';

class PowerRepositoryException extends AppFailure {
  const PowerRepositoryException(super.message, {super.kind, super.details});
}

class PowerRepository extends PrivilegedRepository {
  const PowerRepository({
    required LegionSysfsService sysfsService,
    required PowerProfileService powerProfileService,
    required super.bridgeService,
  }) : _sysfsService = sysfsService,
       _powerProfileService = powerProfileService;

  @override
  Exception wrapBridgeError(AppFailure failure) => PowerRepositoryException(
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

  static const List<PowerLimitSpec> allPowerLimits = [
    PowerLimitSpec(
      id: 'cpu_longterm',
      label: 'CPU sustained (PL1)',
      feature: ControlFeature.cpuLongtermPowerLimit,
      sysfsAttribute: 'cpu_longterm_powerlimit',
      min: 5,
      max: 200,
    ),
    PowerLimitSpec(
      id: 'cpu_shortterm',
      label: 'CPU boost (PL2)',
      feature: ControlFeature.cpuShorttermPowerLimit, // legion_linux/legion.py:CPUShorttermPowerLimit
      sysfsAttribute: 'cpu_shortterm_powerlimit',
      min: 5,
      max: 200,
    ),
    PowerLimitSpec(
      id: 'cpu_peak',
      label: 'CPU Peak Power Limit',
      feature: ControlFeature.cpuPeakPowerLimit, // legion_linux/legion.py:CPUPeakPowerLimit
      sysfsAttribute: 'cpu_peak_powerlimit',
      min: 0,
      max: 200,
    ),
    PowerLimitSpec(
      id: 'cpu_cross_loading',
      label: 'CPU Cross Loading Power Limit',
      feature: ControlFeature.cpuCrossLoadingPowerLimit, // legion_linux/legion.py:CPUCrossLoadingPowerLimit
      sysfsAttribute: 'cpu_cross_loading_powerlimit',
      min: 0,
      max: 100,
    ),
    PowerLimitSpec(
      id: 'cpu_temperature',
      label: 'CPU temperature limit',
      sysfsAttribute: 'cpu_temperature_limit',
      unit: '°C',
      min: 0,
      max: 120,
    ),
    PowerLimitSpec(
      id: 'cpu_apu_sppt',
      label: 'CPU APU SPPT Power Limit',
      feature: ControlFeature.cpuApusPptPowerLimit, // legion_linux/legion.py:CPUAPUSPPTPowerLimit
      sysfsAttribute: 'cpu_apu_sppt_powerlimit',
      min: 0,
      max: 100,
    ),
    PowerLimitSpec(
      id: 'cpu_default',
      label: 'CPU Default Power Limit',
      // The driver exposes this diagnostic with DEVICE_ATTR_RO.
      sysfsAttribute: 'cpu_default_powerlimit',
      min: 0,
      max: 100,
    ),
    PowerLimitSpec(
      id: 'gpu_ctgp',
      label: 'GPU total power (cTGP)',
      feature: ControlFeature.gpuCtgPowerLimit, // legion_linux/legion.py:GPUCTGPPowerLimit
      sysfsAttribute: 'gpu_ctgp_powerlimit',
      min: 0,
      max: 200,
    ),
    PowerLimitSpec(
      id: 'gpu_power_target_offset',
      label: 'GPU AC power-target offset',
      sysfsAttribute: 'gpu_power_target_offset',
      min: 0,
      max: 200,
    ),
    PowerLimitSpec(
      id: 'gpu_ppab',
      label: 'GPU PPAB Power Limit',
      feature: ControlFeature.gpuPpabPowerLimit, // legion_linux/legion.py:GPUPPABPowerLimit
      sysfsAttribute: 'gpu_ppab_powerlimit',
      min: 0,
      max: 200,
    ),
    PowerLimitSpec(
      id: 'gpu_boost_clock',
      label: 'GPU Boost Clock',
      feature: ControlFeature.gpuBoostClock, // legion_linux/legion.py:GPUBoostClock
      sysfsAttribute: 'gpu_boost_clock',
      unit: 'MHz',
      min: 0,
      max: 10000,
    ),
    PowerLimitSpec(
      id: 'gpu_temperature',
      label: 'GPU Temperature Limit',
      feature: ControlFeature.gpuTemperatureLimit, // legion_linux/legion.py:GPUTemperatureLimit
      sysfsAttribute: 'gpu_temperature_limit',
      unit: '°C',
      min: 0,
      max: 120,
    ),
  ];

  Future<PowerSnapshot> loadSnapshot() async {
    final currentRaw = await _sysfsService.readPlatformProfile();
    final choicesRaw = await _sysfsService.readPlatformProfileChoices();
    final cpuOverclock = await _sysfsService.readCpuOverclockMode();
    final gpuOverclock = await _sysfsService.readGpuOverclockMode();
    final onPowerSupply = await _sysfsService.readOnPowerSupplyMode();
    final daemonSnapshot = await _powerProfileService.loadDaemonSnapshot();
    final cpuPolicy = await _sysfsService.readCpuPolicySnapshot();
    final hardwareDefaults = await _loadHardwareDefaults();

    final hardwareProfiles = choicesRaw.isEmpty
        ? daemonSnapshot == null
              ? _fallbackModeValues
              : const <String>[]
        : choicesRaw;
    final source = _powerProfileService.availableProfiles(
      hardwareProfiles: hardwareProfiles,
      daemon: daemonSnapshot,
    );
    final values = <String>[];
    for (final raw in source) {
      final value = PowerMode.fromRaw(raw).value;
      if (value.isNotEmpty && !values.contains(value)) {
        values.add(value);
      }
    }

    final currentMode = currentRaw == null
        ? null
        : PowerMode.fromRaw(currentRaw.trim());

    if (currentMode != null &&
        currentMode.value.isNotEmpty &&
        !values.contains(currentMode.value)) {
      values.insert(0, currentMode.value);
    }

    final availableModes = values.map(PowerMode.new).toList(growable: false);

    final powerLimits = <PowerLimitReading>[];
    for (final spec in allPowerLimits) {
      final value = await _sysfsService.readLegionIntFile(spec.sysfsAttribute);
      if (value != null && value >= spec.effectiveMin && value <= spec.max) {
        powerLimits.add(
          PowerLimitReading(
            spec: spec,
            value: value,
            hardwareDefault: hardwareDefaults[spec.id],
          ),
        );
      }
    }

    return PowerSnapshot(
      currentMode: currentMode,
      availableModes: availableModes,
      powerLimits: powerLimits,
      cpuOverclockEnabled: cpuOverclock,
      gpuOverclockEnabled: gpuOverclock,
      onPowerSupply: onPowerSupply,
      daemonSnapshot: daemonSnapshot,
      cpuPolicy: cpuPolicy,
    );
  }

  Future<void> setPowerMode(PowerMode mode) async {
    await _powerProfileService.setProfile(
      mode.value,
      writePlatformProfile: _setPlatformProfile,
    );
  }

  Future<void> _setPlatformProfile(String profile) async {
    await runControlOperation(
      (client) => client.setFeature(ControlFeature.platformProfile, profile),
      args: [ControlFeature.platformProfile.wireValue, profile],
      method: 'feature.set',
      failurePrefix: 'Failed to set platform power mode to "$profile"',
    );
  }

  Future<void> setPowerLimit(PowerLimitSpec limit, int value) async {
    final feature = limit.feature;
    if (feature == null) {
      throw PowerRepositoryException('${limit.label} is read-only.');
    }
    if (value < limit.effectiveMin || value > limit.max) {
      throw PowerRepositoryException(
        '${limit.label} must be between ${limit.effectiveMin} and ${limit.max}.',
      );
    }

    await _requireLimitWriteContext();

    await runControlOperation(
      (client) => client.setFeature(feature, '$value'),
      args: [feature.wireValue, '$value'],
      method: 'feature.set',
      failurePrefix: 'Failed to set ${limit.label}',
    );
  }

  Future<void> setPowerLimits(List<PowerLimitReading> readings) async {
    for (final reading in readings) {
      if (!reading.spec.isWritable) {
        throw PowerRepositoryException('${reading.spec.label} is read-only.');
      }
      if (reading.value < reading.spec.effectiveMin ||
          reading.value > reading.spec.max) {
        throw PowerRepositoryException(
          '${reading.spec.label} must be between '
          '${reading.spec.effectiveMin} and ${reading.spec.max}.',
        );
      }
    }
    await _requireLimitWriteContext();

    final originals = <String, int>{};
    for (final reading in readings) {
      final value = await _sysfsService.readLegionIntFile(
        reading.spec.sysfsAttribute,
      );
      if (value == null) {
        throw PowerRepositoryException(
          'Could not verify the current ${reading.spec.label}. No limits were changed.',
        );
      }
      originals[reading.spec.id] = value;
    }

    final applied = <PowerLimitReading>[];
    try {
      for (final reading in readings) {
        await runControlOperation(
          (client) =>
              client.setFeature(reading.spec.feature!, '${reading.value}'),
          args: [reading.spec.feature!.wireValue, '${reading.value}'],
          method: 'feature.set',
          failurePrefix: 'Failed to set ${reading.spec.label}',
        );
        applied.add(reading);
      }
    } catch (error) {
      final rollbackFailures = <String>[];
      for (final reading in applied.reversed) {
        try {
          await runControlOperation(
            (client) => client.setFeature(
              reading.spec.feature!,
              '${originals[reading.spec.id]}',
            ),
            args: [
              reading.spec.feature!.wireValue,
              '${originals[reading.spec.id]}',
            ],
            method: 'feature.set',
            failurePrefix: 'Failed to restore ${reading.spec.label}',
          );
        } catch (_) {
          rollbackFailures.add(reading.spec.label);
        }
      }
      if (rollbackFailures.isNotEmpty) {
        final failure = AppFailure.from(error);
        throw PowerRepositoryException(
          '$error Some values could not be restored: ${rollbackFailures.join(', ')}.',
          kind: failure.kind,
          details: failure.details,
        );
      }
      rethrow;
    }
  }

  Future<void> _requireLimitWriteContext() async {
    final profile = await _sysfsService.readPlatformProfile();
    if (profile == null || !PowerMode.fromRaw(profile).isCustom) {
      throw const PowerRepositoryException(
        'Power limits can only be changed in Custom mode.',
      );
    }
    if (await _sysfsService.readOnPowerSupplyMode() != true) {
      throw const PowerRepositoryException(
        'Connect AC power before changing custom power limits.',
      );
    }
  }

  Future<Map<String, int>> _loadHardwareDefaults() async {
    final identity = await Future.wait([
      _sysfsService.readDeviceProductName(),
      _sysfsService.readBiosVersion(),
    ]);
    return powerReferenceLimitsFor(
      productName: identity[0],
      biosVersion: identity[1],
    );
  }

  Future<void> setCpuOverclock(bool enabled) async {
    await _runFeatureToggle(
      feature: ControlFeature.cpuOverclock,
      enabled: enabled,
      settingLabel: 'CPU overclock',
    );
  }

  Future<void> setGpuOverclock(bool enabled) async {
    await _runFeatureToggle(
      feature: ControlFeature.gpuOverclock,
      enabled: enabled,
      settingLabel: 'GPU overclock',
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
