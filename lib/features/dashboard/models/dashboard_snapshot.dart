import 'package:equatable/equatable.dart';

import 'system_status.dart';

class DashboardSnapshot extends Equatable {
  const DashboardSnapshot({
    required this.status,
    required this.availablePowerModes,
    required this.hybridModeEnabled,
    required this.overdriveEnabled,
    required this.batteryConservationEnabled,
    required this.rapidChargingEnabled,
    required this.onPowerSupply,
    required this.recommendedFanPreset,
  });

  factory DashboardSnapshot.initial() => DashboardSnapshot(
    status: SystemStatus.initial(),
    availablePowerModes: const [],
    hybridModeEnabled: null,
    overdriveEnabled: null,
    batteryConservationEnabled: null,
    rapidChargingEnabled: null,
    onPowerSupply: null,
    recommendedFanPreset: null,
  );

  final SystemStatus status;
  final List<String> availablePowerModes;
  final bool? hybridModeEnabled;
  final bool? overdriveEnabled;
  final bool? batteryConservationEnabled;
  final bool? rapidChargingEnabled;
  final bool? onPowerSupply;
  final String? recommendedFanPreset;

  @override
  List<Object?> get props => [
    status,
    availablePowerModes,
    hybridModeEnabled,
    overdriveEnabled,
    batteryConservationEnabled,
    rapidChargingEnabled,
    onPowerSupply,
    recommendedFanPreset,
  ];
}
