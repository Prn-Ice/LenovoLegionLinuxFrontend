/// The fixed files shown in Diagnostics. Write availability follows the actions
/// accepted by LegionControlClient and control/control_commands.cc.
enum HardwareCheck {
  productFamily('product_family', 'Model family'),
  productName('product_name', 'Model identifier'),
  biosVersion('bios_version', 'BIOS version'),
  kernelVersion('kernel_version', 'Kernel version'),
  moduleVersion('module_version', 'Module version'),
  platformProfile('platform_profile', 'Platform profile', writable: true),
  platformProfileChoices(
    'platform_profile_choices',
    'Platform profile choices',
  ),
  hybridMode('hybrid_mode', 'Hybrid/G-Sync state', writable: true),
  overdrive('overdrive', 'Overdrive state', writable: true),
  batteryConservation(
    'battery_conservation',
    'Battery conservation',
    writable: true,
  ),
  rapidCharge('rapid_charge', 'Rapid charging', writable: true),
  alwaysOnUsb('always_on_usb', 'Always-on USB charging', writable: true),
  touchpad('touchpad', 'Touchpad state', writable: true),
  winKey('win_key', 'Win key lock', writable: true),
  cameraPower('camera_power', 'Camera power state'),
  fnLock('fn_lock', 'Fn lock', writable: true),
  keyboardBacklight('keyboard_backlight', 'Keyboard brightness'),
  yLogo('y_logo', 'Y-logo brightness', writable: true),
  ioPortLight('io_port_light', 'I/O-port brightness', writable: true),
  acOnline('ac_online', 'AC adapter online'),
  lockFanController(
    'lock_fan_controller',
    'Fan controller lock',
    writable: true,
  ),
  fanFullspeed('fan_fullspeed', 'Max fan speed toggle', writable: true),
  miniFanCurve('mini_fan_curve', 'Mini fan curve mode', writable: true),
  fan1Rpm('fan1_rpm', 'Fan 1 (RPM)'),
  fan2Rpm('fan2_rpm', 'Fan 2 (RPM)'),
  fan1Provider('fan1_provider', 'Fan 1 provider'),
  fan2Provider('fan2_provider', 'Fan 2 provider'),
  hwmonDiscovery('hwmon_discovery', 'Sensor discovery'),
  ideapadDiscovery('ideapad_discovery', 'Ideapad discovery'),
  ledDiscovery('led_discovery', 'LED discovery'),
  cpuLongterm('cpu_longterm', 'CPU sustained (PL1, W)', writable: true),
  cpuShortterm('cpu_shortterm', 'CPU boost (PL2, W)', writable: true),
  cpuPeak('cpu_peak', 'CPU peak power limit (W)', writable: true),
  cpuCrossLoading(
    'cpu_cross_loading',
    'CPU cross-loading power limit (W)',
    writable: true,
  ),
  cpuTemperature('cpu_temperature', 'CPU temperature limit (°C)'),
  cpuApuSppt('cpu_apu_sppt', 'CPU APU SPPT power limit (W)', writable: true),
  cpuDefault('cpu_default', 'CPU default power limit (W)'),
  gpuCtgp('gpu_ctgp', 'GPU total power (cTGP, W)', writable: true),
  gpuPowerTargetOffset(
    'gpu_power_target_offset',
    'GPU AC power-target offset (W)',
  ),
  gpuPpab('gpu_ppab', 'GPU PPAB power limit (W)', writable: true),
  gpuBoostClock('gpu_boost_clock', 'GPU boost clock (MHz)', writable: true),
  gpuTemperature(
    'gpu_temperature',
    'GPU temperature limit (°C)',
    writable: true,
  ),
  cpuOverclock('cpu_oc', 'CPU overclock', writable: true),
  gpuOverclock('gpu_oc', 'GPU overclock', writable: true);

  const HardwareCheck(this.jsonId, this.label, {this.writable = false});

  final String jsonId;
  final String label;

  /// A write action is implemented and allowed. Writes are still untested.
  final bool writable;
}
