import 'dart:convert';
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

enum ControlFeature {
  platformProfile('PlatformProfileFeature'),
  overdrive('OverdriveFeature'),
  winkey('WinkeyFeature'),
  cpuOverclock('CPUOverclock'),
  gpuOverclock('GPUOverclock'),
  yLogoLight('YLogoLight'),
  ioPortLight('IOPortLight'),
  cpuLongtermPowerLimit('CPULongtermPowerLimit'),
  cpuShorttermPowerLimit('CPUShorttermPowerLimit'),
  cpuPeakPowerLimit('CPUPeakPowerLimit'),
  cpuCrossLoadingPowerLimit('CPUCrossLoadingPowerLimit'),
  cpuApusPptPowerLimit('CPUAPUSPPTPowerLimit'),
  gpuCtgppPowerLimit('GPUCTGPPowerLimit'),
  gpuPpabPowerLimit('GPUPPABPowerLimit'),
  gpuBoostClock('GPUBoostClock'),
  gpuTemperatureLimit('GPUTemperatureLimit');

  const ControlFeature(this.serializedName);

  final String serializedName;
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

/// An argv value for a future caller; this prototype never executes it.
class HelperCommand {
  HelperCommand(List<String> arguments)
    : arguments = List.unmodifiable(arguments);

  final List<String> arguments;
}

/// Validates a feature value and constructs the native helper's argv.
HelperCommand buildFeatureCommand(ControlFeature feature, FeatureValue value) {
  final serializedValue = switch ((feature, value)) {
    (ControlFeature.platformProfile, ProfileValue(:final value)) =>
      value.serializedName,
    (ControlFeature.overdrive, BooleanValue(:final value)) => value ? '1' : '0',
    (ControlFeature.winkey, BooleanValue(:final value)) => value ? '1' : '0',
    (ControlFeature.cpuOverclock, BooleanValue(:final value)) =>
      value ? '1' : '0',
    (ControlFeature.gpuOverclock, BooleanValue(:final value)) =>
      value ? '1' : '0',
    (ControlFeature.yLogoLight, BooleanValue(:final value)) =>
      value ? '1' : '0',
    (ControlFeature.ioPortLight, BooleanValue(:final value)) =>
      value ? '1' : '0',
    (ControlFeature.cpuLongtermPowerLimit, IntegerValue(:final value)) =>
      _boundedInteger(value, 5, 200),
    (ControlFeature.cpuShorttermPowerLimit, IntegerValue(:final value)) =>
      _boundedInteger(value, 5, 200),
    (ControlFeature.cpuPeakPowerLimit, IntegerValue(:final value)) =>
      _boundedInteger(value, 1, 200),
    (ControlFeature.cpuCrossLoadingPowerLimit, IntegerValue(:final value)) =>
      _boundedInteger(value, 1, 100),
    (ControlFeature.cpuApusPptPowerLimit, IntegerValue(:final value)) =>
      _boundedInteger(value, 1, 100),
    (ControlFeature.gpuCtgppPowerLimit, IntegerValue(:final value)) =>
      _boundedInteger(value, 1, 200),
    (ControlFeature.gpuPpabPowerLimit, IntegerValue(:final value)) =>
      _boundedInteger(value, 1, 200),
    (ControlFeature.gpuBoostClock, IntegerValue(:final value)) =>
      _boundedInteger(value, 1, 10000),
    (ControlFeature.gpuTemperatureLimit, IntegerValue(:final value)) =>
      _boundedInteger(value, 1, 120),
    _ => throw const FormatException('unsupported feature or value'),
  };
  return HelperCommand([
    '--donotexpecthwmon',
    'set-feature',
    feature.serializedName,
    serializedValue,
  ]);
}

String _boundedInteger(int value, int minimum, int maximum) {
  if (value < minimum || value > maximum) {
    throw const FormatException('unsupported feature or value');
  }
  return value.toString();
}

/// Parses the strings received at the native boundary before building argv.
HelperCommand buildFeatureFromSerializedInput(
  String featureName,
  String value,
) {
  validateBoundedInput(featureName, 'feature');
  validateBoundedInput(value, 'value');
  final feature = ControlFeature.values.firstWhere(
    (candidate) => candidate.serializedName == featureName,
    orElse: () => throw const FormatException('unsupported feature or value'),
  );
  if (feature == ControlFeature.platformProfile) {
    final profile = PlatformProfile.values.firstWhere(
      (candidate) => candidate.serializedName == value,
      orElse: () => throw const FormatException('unsupported feature or value'),
    );
    return buildFeatureCommand(feature, ProfileValue(profile));
  }
  if ({
    ControlFeature.overdrive,
    ControlFeature.winkey,
    ControlFeature.cpuOverclock,
    ControlFeature.gpuOverclock,
    ControlFeature.yLogoLight,
    ControlFeature.ioPortLight,
  }.contains(feature)) {
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

/// Applies the native 128-byte text bound before an external value is parsed.
void validateBoundedInput(String value, String label) {
  if (utf8.encode(value).length > helperInputLimit) {
    throw FormatException('$label exceeds maximum length');
  }
}

/// Parses a serialized capability before selecting its allow-listed command.
ControlCapability parseCapability(String value) {
  validateBoundedInput(value, 'toggle');
  return ControlCapability.values.firstWhere(
    (candidate) => candidate.serializedName == value,
    orElse: () => throw const FormatException('unsupported capability'),
  );
}

FanPreset parsePreset(String value) {
  validateBoundedInput(value, 'preset');
  return FanPreset.values.firstWhere(
    (candidate) => candidate.serializedName == value,
    orElse: () => throw const FormatException('unsupported fan preset'),
  );
}

ServiceId parseServiceId(String value) {
  validateBoundedInput(value, 'service id');
  return ServiceId.values.firstWhere(
    (candidate) => candidate.serializedName == value,
    orElse: () => throw const FormatException('unsupported service id'),
  );
}

GraphicsMode parseGraphicsMode(String value) {
  validateBoundedInput(value, 'graphics mode');
  return switch (value) {
    'hybrid' => GraphicsMode.hybrid,
    'hybrid-igpu-only' => GraphicsMode.hybridIgpuOnly,
    'discrete' => GraphicsMode.discrete,
    _ => throw const FormatException('unsupported graphics mode'),
  };
}

BootGraphicsMode parseBootGraphicsMode(String value) {
  validateBoundedInput(value, 'graphics mode');
  return switch (value) {
    'hybrid' => BootGraphicsMode.hybrid,
    'hybrid-igpu-only' => BootGraphicsMode.hybridIgpuOnly,
    _ => throw const FormatException(
      'only hybrid and hybrid-igpu-only can be requested for next boot',
    ),
  };
}

/// Checks a payload before any byte scan; the native runtime owns its temp file.
void validatePayload(List<int> bytes, int maximumSize) {
  if (bytes.length > maximumSize) {
    throw const FormatException('payload exceeds maximum size');
  }
  if (bytes.isEmpty) {
    throw const FormatException('payload must not be empty');
  }
  if (bytes.any((byte) => byte < 0 || byte > 255)) {
    throw const FormatException('payload contains a non-byte value');
  }
}

/// Builds one allow-listed toggle command without invoking the backend.
HelperCommand buildToggleCommand(ControlCapability capability, bool on) {
  final command = '${capability.commandName}-${on ? 'enable' : 'disable'}';
  return HelperCommand([
    if (capability.needsNoHardwareMonitorFlag) '--donotexpecthwmon',
    command,
  ]);
}

HelperCommand buildPresetCommand(FanPreset preset) =>
    HelperCommand(['fancurve-write-preset-to-hw', preset.serializedName]);

HelperCommand buildCurrentPresetCommand() =>
    HelperCommand(['fancurve-write-current-preset-to-hw']);

String _filePath(File file) {
  if (file.path.isEmpty) {
    throw const FormatException('file path must not be empty');
  }
  return file.path;
}

// The path is an argv placeholder; production IPC first writes a validated
// payload to a private native temporary file and passes that path instead.
HelperCommand buildFanCurveFileCommand(File curve) =>
    HelperCommand(['fancurve-write-file-to-hw', _filePath(curve)]);

HelperCommand buildBootLogoCommand(File image) => HelperCommand([
  '--donotexpecthwmon',
  'boot-logo',
  'enable',
  _filePath(image),
]);

HelperCommand buildRestoreBootLogoCommand() =>
    HelperCommand(['--donotexpecthwmon', 'boot-logo', 'restore']);

HelperCommand buildConservationCommand(int lower, int upper) {
  if (lower < 0 || upper < 0 || lower > 100 || upper > 100 || lower > upper) {
    throw const FormatException('invalid conservation limits');
  }
  return HelperCommand([
    '--donotexpecthwmon',
    'custom-conservation-mode-apply',
    '$lower',
    '$upper',
  ]);
}

HelperCommand buildServiceCommand(ServiceId service, bool on) =>
    HelperCommand([on ? 'enable' : 'disable', '--now', ...service.units]);

HelperCommand buildGraphicsCommand(GraphicsMode mode) => HelperCommand([
  '--donotexpecthwmon',
  'graphics-mode',
  'set',
  switch (mode) {
    GraphicsMode.hybrid => 'hybrid',
    GraphicsMode.hybridIgpuOnly => 'hybrid-igpu-only',
    GraphicsMode.discrete => 'discrete',
  },
  '--json',
]);

HelperCommand buildBootGraphicsCommand(BootGraphicsMode mode) =>
    HelperCommand(['request', _bootGraphicsName(mode)]);

String _bootGraphicsName(BootGraphicsMode mode) => switch (mode) {
  BootGraphicsMode.hybrid => 'hybrid',
  BootGraphicsMode.hybridIgpuOnly => 'hybrid-igpu-only',
};

/// Applies PR30's exit meanings only within the selected backend category.
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
