/// Named values accepted by the privileged control service.
///
/// Wire spellings stay here at the service boundary instead of being repeated
/// by feature repositories.
enum ControlToggle {
  hybridMode('hybrid-mode'),
  batteryConservation('battery-conservation'),
  rapidCharging('rapid-charging'),
  alwaysOnUsbCharging('always-on-usb-charging'),
  touchpad('touchpad'),
  fnLock('fn-lock'),
  miniFanCurve('mini-fan-curve'),
  lockFanController('lock-fan-controller'),
  maximumFanSpeed('maximum-fan-speed');

  const ControlToggle(this.wireValue);
  final String wireValue;
}

enum ControlFeature {
  platformProfile('PlatformProfileFeature'),
  overdrive('OverdriveFeature'),
  winkey('WinkeyFeature'),
  cpuLongtermPowerLimit('CPULongtermPowerLimit'),
  cpuShorttermPowerLimit('CPUShorttermPowerLimit'),
  cpuPeakPowerLimit('CPUPeakPowerLimit'),
  cpuCrossLoadingPowerLimit('CPUCrossLoadingPowerLimit'),
  cpuApusPptPowerLimit('CPUAPUSPPTPowerLimit'),
  gpuCtgPowerLimit('GPUCTGPPowerLimit'),
  gpuPpabPowerLimit('GPUPPABPowerLimit'),
  gpuBoostClock('GPUBoostClock'),
  gpuTemperatureLimit('GPUTemperatureLimit'),
  cpuOverclock('CPUOverclock'),
  gpuOverclock('GPUOverclock'),
  yLogoLight('YLogoLight'),
  ioPortLight('IOPortLight');

  const ControlFeature(this.wireValue);
  final String wireValue;
}

enum ControlService {
  powerProfilesDaemon('power_profiles_daemon'),
  legiondStack('legiond_stack');

  const ControlService(this.wireValue);
  final String wireValue;
}

enum ControlFanPreset {
  quietBattery('quiet-battery'),
  balancedBattery('balanced-battery'),
  performanceBattery('performance-battery'),
  balancedPerformanceBattery('balanced-performance-battery'),
  quietAc('quiet-ac'),
  balancedAc('balanced-ac'),
  performanceAc('performance-ac'),
  balancedPerformanceAc('balanced-performance-ac');

  const ControlFanPreset(this.wireValue);
  final String wireValue;

  static ControlFanPreset parse(String value) => values.firstWhere(
    (preset) => preset.wireValue == value,
    orElse: () => throw FormatException('Unsupported fan preset: $value'),
  );
}
