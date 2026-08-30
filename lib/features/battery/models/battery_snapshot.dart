import 'package:equatable/equatable.dart';

class BatterySnapshot extends Equatable {
  const BatterySnapshot({
    required this.batteryConservationEnabled,
    required this.batteryConservationSupported,
    required this.rapidChargingEnabled,
    required this.rapidChargingSupported,
    required this.batteryPercent,
    required this.batteryCharging,
    required this.batteryPowerDrawW,
    required this.cycleCounts,
    required this.fullCapacityWh,
    required this.designCapacityWh,
    required this.currentCapacityWh,
    required this.batteryTempC,
    this.batteryStatus,
    this.alwaysOnUsbEnabled,
    this.alwaysOnUsbSupported = false,
    this.voltageV,
    this.manufacturer,
    this.modelName,
    this.serialNumber,
  });

  final bool? batteryConservationEnabled;
  final bool batteryConservationSupported;
  final bool? rapidChargingEnabled;
  final bool rapidChargingSupported;
  final int? batteryPercent;
  final bool? batteryCharging;
  final double? batteryPowerDrawW;
  final int? cycleCounts;
  final double? fullCapacityWh;
  final double? designCapacityWh;
  final double? currentCapacityWh;
  final double? batteryTempC;
  final String? batteryStatus;
  final bool? alwaysOnUsbEnabled;
  final bool alwaysOnUsbSupported;
  final double? voltageV;
  final String? manufacturer;
  final String? modelName;
  final String? serialNumber;

  @override
  List<Object?> get props => [
    batteryConservationEnabled,
    batteryConservationSupported,
    rapidChargingEnabled,
    rapidChargingSupported,
    batteryPercent,
    batteryCharging,
    batteryPowerDrawW,
    cycleCounts,
    fullCapacityWh,
    designCapacityWh,
    currentCapacityWh,
    batteryTempC,
    batteryStatus,
    alwaysOnUsbEnabled,
    alwaysOnUsbSupported,
    voltageV,
    manufacturer,
    modelName,
    serialNumber,
  ];
}
