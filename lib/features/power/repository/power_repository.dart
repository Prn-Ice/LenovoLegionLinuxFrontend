import '../../../core/data/privileged_repository.dart';
import '../../../core/services/legion_sysfs_service.dart';
import '../models/power_limit.dart';
import '../models/power_mode.dart';
import '../models/power_snapshot.dart';

class PowerRepositoryException implements Exception {
  const PowerRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PowerRepository extends PrivilegedRepository {
  const PowerRepository({
    required LegionSysfsService sysfsService,
    required super.bridgeService,
  }) : _sysfsService = sysfsService;

  @override
  Exception wrapBridgeError(String message) =>
      PowerRepositoryException(message);

  final LegionSysfsService _sysfsService;

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
      featureName:
          'CPULongtermPowerLimit', // legion_linux/legion.py:CPULongtermPowerLimit
      sysfsAttribute: 'cpu_longterm_powerlimit',
      min: 5,
      max: 200,
    ),
    PowerLimitSpec(
      id: 'cpu_shortterm',
      label: 'CPU boost (PL2)',
      featureName:
          'CPUShorttermPowerLimit', // legion_linux/legion.py:CPUShorttermPowerLimit
      sysfsAttribute: 'cpu_shortterm_powerlimit',
      min: 5,
      max: 200,
    ),
    PowerLimitSpec(
      id: 'cpu_peak',
      label: 'CPU Peak Power Limit',
      featureName:
          'CPUPeakPowerLimit', // legion_linux/legion.py:CPUPeakPowerLimit
      sysfsAttribute: 'cpu_peak_powerlimit',
      min: 0,
      max: 200,
    ),
    PowerLimitSpec(
      id: 'cpu_cross_loading',
      label: 'CPU Cross Loading Power Limit',
      featureName:
          'CPUCrossLoadingPowerLimit', // legion_linux/legion.py:CPUCrossLoadingPowerLimit
      sysfsAttribute: 'cpu_cross_loading_powerlimit',
      min: 0,
      max: 100,
    ),
    PowerLimitSpec(
      id: 'cpu_apu_sppt',
      label: 'CPU APU SPPT Power Limit',
      featureName:
          'CPUAPUSPPTPowerLimit', // legion_linux/legion.py:CPUAPUSPPTPowerLimit
      sysfsAttribute: 'cpu_apu_sppt_powerlimit',
      min: 0,
      max: 100,
    ),
    PowerLimitSpec(
      id: 'cpu_default',
      label: 'CPU Default Power Limit',
      featureName:
          'CPUDefaultPowerLimit', // legion_linux/legion.py:CPUDefaultPowerLimit
      sysfsAttribute: 'cpu_default_powerlimit',
      min: 0,
      max: 100,
    ),
    PowerLimitSpec(
      id: 'gpu_ctgp',
      label: 'GPU total power (cTGP)',
      featureName:
          'GPUCTGPPowerLimit', // legion_linux/legion.py:GPUCTGPPowerLimit
      sysfsAttribute: 'gpu_ctgp_powerlimit',
      min: 0,
      max: 200,
    ),
    PowerLimitSpec(
      id: 'gpu_ppab',
      label: 'GPU PPAB Power Limit',
      featureName:
          'GPUPPABPowerLimit', // legion_linux/legion.py:GPUPPABPowerLimit
      sysfsAttribute: 'gpu_ppab_powerlimit',
      min: 0,
      max: 200,
    ),
    PowerLimitSpec(
      id: 'gpu_boost_clock',
      label: 'GPU Boost Clock',
      featureName: 'GPUBoostClock', // legion_linux/legion.py:GPUBoostClock
      sysfsAttribute: 'gpu_boost_clock',
      unit: 'MHz',
      min: 0,
      max: 10000,
    ),
    PowerLimitSpec(
      id: 'gpu_temperature',
      label: 'GPU Temperature Limit',
      featureName:
          'GPUTemperatureLimit', // legion_linux/legion.py:GPUTemperatureLimit
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

    final values = <String>[];
    final source = choicesRaw.isEmpty ? _fallbackModeValues : choicesRaw;
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
      if (value != null) {
        powerLimits.add(PowerLimitReading(spec: spec, value: value));
      }
    }

    return PowerSnapshot(
      currentMode: currentMode,
      availableModes: availableModes,
      powerLimits: powerLimits,
      cpuOverclockEnabled: cpuOverclock,
      gpuOverclockEnabled: gpuOverclock,
    );
  }

  Future<void> setPowerMode(PowerMode mode) async {
    await runPrivilegedCommand(
      [
        'set-feature',
        'PlatformProfileFeature',
        mode.value,
      ], // legion_linux/legion.py:PlatformProfileFeature
      method: 'feature.set',
      failurePrefix: 'Failed to set power mode to ${mode.label}',
    );
  }

  Future<void> setPowerLimit(PowerLimitSpec limit, int value) async {
    if (value < limit.min || value > limit.max) {
      throw PowerRepositoryException(
        '${limit.label} must be between ${limit.min} and ${limit.max}.',
      );
    }

    await runPrivilegedCommand(
      ['set-feature', limit.featureName, '$value'],
      method: 'feature.set',
      failurePrefix: 'Failed to set ${limit.label}',
    );
  }

  Future<void> setCpuOverclock(bool enabled) async {
    await _runFeatureToggle(
      featureName: 'CPUOverclock', // legion_linux/legion.py:CPUOverclock
      enabled: enabled,
      settingLabel: 'CPU overclock',
      detectUnavailableResponse: true,
    );
  }

  Future<void> setGpuOverclock(bool enabled) async {
    await _runFeatureToggle(
      featureName: 'GPUOverclock', // legion_linux/legion.py:GPUOverclock
      enabled: enabled,
      settingLabel: 'GPU overclock',
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
