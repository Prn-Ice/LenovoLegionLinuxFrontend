class BatteryDevicesSnapshot {
  const BatteryDevicesSnapshot({
    required this.batteryConservationEnabled,
    required this.rapidChargingEnabled,
    required this.alwaysOnUsbChargingEnabled,
    required this.alwaysOnUsbWriteSupported,
    required this.touchpadEnabled,
    required this.winKeyEnabled,
    required this.cameraPowerEnabled,
  });

  final bool? batteryConservationEnabled;
  final bool? rapidChargingEnabled;
  final bool? alwaysOnUsbChargingEnabled;
  final bool alwaysOnUsbWriteSupported;
  final bool? touchpadEnabled;
  final bool? winKeyEnabled;
  final bool? cameraPowerEnabled;
}
