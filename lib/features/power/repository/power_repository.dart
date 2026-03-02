import '../../../core/services/legion_frontend_bridge_service.dart';
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

class PowerRepository {
  const PowerRepository({
    required LegionSysfsService sysfsService,
    required LegionFrontendBridgeService bridgeService,
  }) : _sysfsService = sysfsService,
       _bridgeService = bridgeService;

  final LegionSysfsService _sysfsService;
  final LegionFrontendBridgeService _bridgeService;

  static const List<String> _fallbackModeValues = [
    'quiet',
    'balanced',
    'performance',
    'balanced-performance',
  ];

  static const List<PowerLimitSpec> allPowerLimits = [
    PowerLimitSpec(
      id: 'cpu_longterm',
      label: 'CPU Long Term Power Limit',
      featureName: 'CPULongtermPowerLimit',
      sysfsPath:
          '/sys/module/legion_laptop/drivers/platform:legion/PNP0C09:00/cpu_longterm_powerlimit',
      min: 5,
      max: 200,
    ),
    PowerLimitSpec(
      id: 'cpu_shortterm',
      label: 'CPU Short Term Power Limit',
      featureName: 'CPUShorttermPowerLimit',
      sysfsPath:
          '/sys/module/legion_laptop/drivers/platform:legion/PNP0C09:00/cpu_shortterm_powerlimit',
      min: 5,
      max: 200,
    ),
    PowerLimitSpec(
      id: 'cpu_peak',
      label: 'CPU Peak Power Limit',
      featureName: 'CPUPeakPowerLimit',
      sysfsPath:
          '/sys/module/legion_laptop/drivers/platform:legion/PNP0C09:00/cpu_peak_powerlimit',
      min: 0,
      max: 200,
    ),
    PowerLimitSpec(
      id: 'cpu_cross_loading',
      label: 'CPU Cross Loading Power Limit',
      featureName: 'CPUCrossLoadingPowerLimit',
      sysfsPath:
          '/sys/module/legion_laptop/drivers/platform:legion/PNP0C09:00/cpu_cross_loading_powerlimit',
      min: 0,
      max: 100,
    ),
    PowerLimitSpec(
      id: 'cpu_apu_sppt',
      label: 'CPU APU SPPT Power Limit',
      featureName: 'CPUAPUSPPTPowerLimit',
      sysfsPath:
          '/sys/module/legion_laptop/drivers/platform:legion/PNP0C09:00/cpu_apu_sppt_powerlimit',
      min: 0,
      max: 100,
    ),
    PowerLimitSpec(
      id: 'gpu_ctgp',
      label: 'GPU cTGP Power Limit',
      featureName: 'GPUCTGPPowerLimit',
      sysfsPath:
          '/sys/module/legion_laptop/drivers/platform:legion/PNP0C09:00/gpu_ctgp_powerlimit',
      min: 0,
      max: 200,
    ),
    PowerLimitSpec(
      id: 'gpu_ppab',
      label: 'GPU PPAB Power Limit',
      featureName: 'GPUPPABPowerLimit',
      sysfsPath:
          '/sys/module/legion_laptop/drivers/platform:legion/PNP0C09:00/gpu_ppab_powerlimit',
      min: 0,
      max: 200,
    ),
  ];

  Future<PowerSnapshot> loadSnapshot() async {
    final currentRaw = await _sysfsService.readPlatformProfile();
    final choicesRaw = await _sysfsService.readPlatformProfileChoices();

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
      final value = await _sysfsService.readIntFile(spec.sysfsPath);
      if (value != null) {
        powerLimits.add(PowerLimitReading(spec: spec, value: value));
      }
    }

    return PowerSnapshot(
      currentMode: currentMode,
      availableModes: availableModes,
      powerLimits: powerLimits,
    );
  }

  Future<void> setPowerMode(PowerMode mode) async {
    try {
      await _bridgeService.runPrivilegedCommand(
        method: 'feature.set',
        args: ['set-feature', 'PlatformProfileFeature', mode.value],
      );
    } on LegionBridgeException catch (error) {
      final details = error.details;
      final message = details.isEmpty
          ? 'Failed to set power mode to ${mode.label}.'
          : 'Failed to set power mode to ${mode.label}: $details';

      throw PowerRepositoryException(message);
    }
  }

  Future<void> setPowerLimit(PowerLimitSpec limit, int value) async {
    if (value < limit.min || value > limit.max) {
      throw PowerRepositoryException(
        '${limit.label} must be between ${limit.min} and ${limit.max}.',
      );
    }

    try {
      await _bridgeService.runPrivilegedCommand(
        method: 'feature.set',
        args: ['set-feature', limit.featureName, '$value'],
      );
    } on LegionBridgeException catch (error) {
      final details = error.details;
      final message = details.isEmpty
          ? 'Failed to set ${limit.label}.'
          : 'Failed to set ${limit.label}: $details';

      throw PowerRepositoryException(message);
    }
  }
}
