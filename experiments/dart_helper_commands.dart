import 'dart:io';

const helperInputLimit = 128;
const fanCurvePayloadLimit = 64 * 1024;
const bootLogoPayloadLimit = 16 * 1024 * 1024;

enum BackendCategory { cli, graphics, systemctl, bootHelper }

enum BackendOutcome {
  success,
  commandFailed,
  unavailable,
  notSupported,
  graphicsBlocked,
  graphicsPending,
}

enum CliExit { success, failed, unavailable, featureNotFound }

enum ControlFeature {
  platformProfile('PlatformProfileFeature'),
  overdrive('OverdriveFeature'),
  winkey('WinkeyFeature'),
  cpuOverclock('CPUOverclock'),
  gpuOverclock('GPUOverclock'),
  yLogoLight('YLogoLight'),
  ioPortLight('IOPortLight'),
  cpuLongtermPowerLimit('CPULongtermPowerLimit', 5, 200),
  cpuShorttermPowerLimit('CPUShorttermPowerLimit', 5, 200),
  cpuPeakPowerLimit('CPUPeakPowerLimit', 1, 200),
  cpuCrossLoadingPowerLimit('CPUCrossLoadingPowerLimit', 1, 100),
  cpuApusPptPowerLimit('CPUAPUSPPTPowerLimit', 1, 100),
  gpuCtgppPowerLimit('GPUCTGPPowerLimit', 1, 200),
  gpuPpabPowerLimit('GPUPPABPowerLimit', 1, 200),
  gpuBoostClock('GPUBoostClock', 1, 10000),
  gpuTemperatureLimit('GPUTemperatureLimit', 1, 120);

  const ControlFeature(this.serializedName, [this.minimum, this.maximum]);

  final String serializedName;
  final int? minimum;
  final int? maximum;

  bool get isBoolean => minimum == null && this != platformProfile;
  bool get isInteger => minimum != null;
}

enum PlatformProfile {
  quiet('quiet'),
  lowPower('low-power'),
  powerSaver('power-saver'),
  balanced('balanced'),
  performance('performance'),
  balancedPerformance('balanced-performance'),
  custom('custom'),
  maxPower('max-power');

  const PlatformProfile(this.serializedName);

  final String serializedName;
}

enum ControlCapability {
  hybridMode('hybrid-mode', 'hybrid-mode', true),
  batteryConservation('battery-conservation', 'batteryconservation', true),
  rapidCharging('rapid-charging', 'rapid-charging', true),
  alwaysOnUsbCharging('always-on-usb-charging', 'always-on-usb-charging', true),
  touchpad('touchpad', 'touchpad', true),
  fnLock('fn-lock', 'fnlock', true),
  miniFanCurve('mini-fan-curve', 'minifancurve', false),
  lockFanController('lock-fan-controller', 'lockfancontroller', false),
  maximumFanSpeed('maximum-fan-speed', 'maximumfanspeed', false);

  const ControlCapability(
    this.serializedName,
    this.commandName,
    this.needsNoHardwareMonitorFlag,
  );

  final String serializedName;
  final String commandName;
  final bool needsNoHardwareMonitorFlag;
}

enum FanPreset {
  quietBattery('quiet-battery'),
  balancedBattery('balanced-battery'),
  performanceBattery('performance-battery'),
  balancedPerformanceBattery('balanced-performance-battery'),
  quietAc('quiet-ac'),
  balancedAc('balanced-ac'),
  performanceAc('performance-ac'),
  balancedPerformanceAc('balanced-performance-ac');

  const FanPreset(this.serializedName);

  final String serializedName;
}

enum ServiceId {
  powerProfilesDaemon('power_profiles_daemon', [
    'power-profiles-daemon.service',
  ]),
  legiondStack('legiond_stack', [
    'legiond.service',
    'legiond-onresume.service',
    'legiond-cpuset.service',
    'legiond-cpuset.timer',
  ]);

  const ServiceId(this.serializedName, this.units);

  final String serializedName;
  final List<String> units;
}

enum GraphicsMode { hybrid, hybridIgpuOnly, discrete }

enum BootGraphicsMode { hybrid, hybridIgpuOnly }

sealed class FeatureValue {
  const FeatureValue();
}

final class ProfileValue extends FeatureValue {
  const ProfileValue(this.value);

  final PlatformProfile value;
}

final class BooleanValue extends FeatureValue {
  const BooleanValue(this.value);

  final bool value;
}

final class IntegerValue extends FeatureValue {
  const IntegerValue(this.value);

  final int value;
}

class CommandBuildResult {
  const CommandBuildResult.success(this.arguments) : error = null;

  const CommandBuildResult.failure(this.error) : arguments = null;

  final List<String>? arguments;
  final String? error;

  bool get isSuccess => arguments != null;
}

CommandBuildResult buildFeatureCommand(
  ControlFeature feature,
  FeatureValue value,
) {
  final serializedValue = switch ((feature, value)) {
    (ControlFeature.platformProfile, ProfileValue(:final value)) =>
      value.serializedName,
    (final feature, BooleanValue(:final value)) when feature.isBoolean =>
      value ? '1' : '0',
    (final feature, IntegerValue(:final value)) when feature.isInteger =>
      _boundedInteger(feature, value),
    _ => null,
  };
  if (serializedValue == null) {
    return const CommandBuildResult.failure('unsupported feature or value');
  }
  return CommandBuildResult.success([
    '--donotexpecthwmon',
    'set-feature',
    feature.serializedName,
    serializedValue,
  ]);
}

String? _boundedInteger(ControlFeature feature, int value) {
  if (feature.minimum == null || feature.maximum == null) return null;
  if (value < feature.minimum! || value > feature.maximum!) return null;
  return value.toString();
}

CommandBuildResult buildFeatureFromSerializedInput(
  String featureName,
  String value,
) {
  _requireBounded(featureName, 'feature');
  _requireBounded(value, 'value');
  final feature = ControlFeature.values.firstWhere(
    (candidate) => candidate.serializedName == featureName,
    orElse: () => throw const FormatException('unsupported feature'),
  );
  if (feature == ControlFeature.platformProfile) {
    final profile = PlatformProfile.values.firstWhere(
      (candidate) => candidate.serializedName == value,
      orElse: () => throw const FormatException('unsupported feature or value'),
    );
    return buildFeatureCommand(feature, ProfileValue(profile));
  }
  if (feature.isBoolean) {
    if (value != '0' && value != '1') {
      throw const FormatException('unsupported feature or value');
    }
    return buildFeatureCommand(feature, BooleanValue(value == '1'));
  }
  if (!RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(value)) {
    throw const FormatException('unsupported feature or value');
  }
  final integer = int.tryParse(value);
  if (integer == null) {
    throw const FormatException('unsupported feature or value');
  }
  return buildFeatureCommand(feature, IntegerValue(integer));
}

void _requireBounded(String value, String label) {
  if (value.length > helperInputLimit) {
    throw FormatException('$label exceeds maximum length');
  }
}

ControlCapability parseCapability(String value) {
  _requireBounded(value, 'toggle');
  return ControlCapability.values.firstWhere(
    (candidate) => candidate.serializedName == value,
    orElse: () => throw const FormatException('unsupported capability'),
  );
}

FanPreset parsePreset(String value) {
  _requireBounded(value, 'preset');
  return FanPreset.values.firstWhere(
    (candidate) => candidate.serializedName == value,
    orElse: () => throw const FormatException('unsupported fan preset'),
  );
}

ServiceId parseServiceId(String value) {
  _requireBounded(value, 'service id');
  return ServiceId.values.firstWhere(
    (candidate) => candidate.serializedName == value,
    orElse: () => throw const FormatException('unsupported service id'),
  );
}

GraphicsMode parseGraphicsMode(String value) {
  _requireBounded(value, 'graphics mode');
  return switch (value) {
    'hybrid' => GraphicsMode.hybrid,
    'hybrid-igpu-only' => GraphicsMode.hybridIgpuOnly,
    'discrete' => GraphicsMode.discrete,
    _ => throw const FormatException('unsupported graphics mode'),
  };
}

BootGraphicsMode parseBootGraphicsMode(String value) {
  _requireBounded(value, 'graphics mode');
  return switch (value) {
    'hybrid' => BootGraphicsMode.hybrid,
    'hybrid-igpu-only' => BootGraphicsMode.hybridIgpuOnly,
    _ => throw const FormatException(
      'only hybrid and hybrid-igpu-only can be requested for next boot',
    ),
  };
}

CommandBuildResult validatePayload(List<int> bytes, int maximumSize) {
  if (bytes.any((byte) => byte < 0 || byte > 255)) {
    return const CommandBuildResult.failure(
      'payload contains a non-byte value',
    );
  }
  if (bytes.isEmpty) {
    return const CommandBuildResult.failure('payload must not be empty');
  }
  if (bytes.length > maximumSize) {
    return const CommandBuildResult.failure('payload exceeds maximum size');
  }
  return const CommandBuildResult.success([]);
}

CommandBuildResult buildToggleCommand(ControlCapability capability, bool on) {
  final command = '${capability.commandName}-${on ? 'enable' : 'disable'}';
  return CommandBuildResult.success([
    if (capability.needsNoHardwareMonitorFlag) '--donotexpecthwmon',
    command,
  ]);
}

CommandBuildResult buildPresetCommand(FanPreset preset) =>
    CommandBuildResult.success([
      'fancurve-write-preset-to-hw',
      preset.serializedName,
    ]);

CommandBuildResult buildCurrentPresetCommand() =>
    const CommandBuildResult.success(['fancurve-write-current-preset-to-hw']);

CommandBuildResult buildFanCurveFileCommand(File curve) =>
    _fileCommand('fancurve-write-file-to-hw', curve);

CommandBuildResult buildBootLogoCommand(File image) =>
    _fileCommand('--donotexpecthwmon boot-logo enable', image);

CommandBuildResult _fileCommand(String command, File file) {
  final path = file.path;
  if (path.isEmpty) {
    return const CommandBuildResult.failure('file path must not be empty');
  }
  if (command.startsWith('--donotexpecthwmon')) {
    return CommandBuildResult.success([
      '--donotexpecthwmon',
      'boot-logo',
      'enable',
      path,
    ]);
  }
  return CommandBuildResult.success([command, path]);
}

CommandBuildResult buildRestoreBootLogoCommand() =>
    const CommandBuildResult.success([
      '--donotexpecthwmon',
      'boot-logo',
      'restore',
    ]);

CommandBuildResult buildConservationCommand(int lower, int upper) {
  if (lower < 0 || upper < 0 || lower > 100 || upper > 100 || lower > upper) {
    return const CommandBuildResult.failure('invalid conservation limits');
  }
  return CommandBuildResult.success([
    '--donotexpecthwmon',
    'custom-conservation-mode-apply',
    '$lower',
    '$upper',
  ]);
}

CommandBuildResult buildServiceCommand(ServiceId service, bool on) =>
    CommandBuildResult.success([
      on ? 'enable' : 'disable',
      '--now',
      ...service.units,
    ]);

CommandBuildResult buildGraphicsCommand(GraphicsMode mode) =>
    CommandBuildResult.success([
      '--donotexpecthwmon',
      'graphics-mode',
      'set',
      mode.name == 'hybridIgpuOnly' ? 'hybrid-igpu-only' : mode.name,
      '--json',
    ]);

CommandBuildResult buildBootGraphicsCommand(BootGraphicsMode mode) =>
    CommandBuildResult.success(['request', _bootGraphicsName(mode)]);

String _bootGraphicsName(BootGraphicsMode mode) =>
    mode == BootGraphicsMode.hybridIgpuOnly ? 'hybrid-igpu-only' : 'hybrid';

BackendOutcome classifyBackendExit(BackendCategory backend, int exitCode) {
  if (exitCode == 0) return BackendOutcome.success;
  if (backend == BackendCategory.cli) {
    return switch (exitCode) {
      2 => BackendOutcome.unavailable,
      3 => BackendOutcome.notSupported,
      _ => BackendOutcome.commandFailed,
    };
  }
  if (backend == BackendCategory.graphics) {
    return switch (exitCode) {
      2 => BackendOutcome.graphicsBlocked,
      3 => BackendOutcome.graphicsPending,
      _ => BackendOutcome.commandFailed,
    };
  }
  return BackendOutcome.commandFailed;
}

BackendOutcome classifyCliExit(int exitCode) =>
    classifyBackendExit(BackendCategory.cli, exitCode);
