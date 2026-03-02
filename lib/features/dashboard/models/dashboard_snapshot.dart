import 'package:equatable/equatable.dart';

import 'system_status.dart';

class DashboardSnapshot extends Equatable {
  const DashboardSnapshot({
    required this.status,
    required this.availablePowerModes,
    required this.hybridModeEnabled,
    required this.onPowerSupply,
    required this.recommendedFanPreset,
  });

  factory DashboardSnapshot.initial() => DashboardSnapshot(
    status: SystemStatus.initial(),
    availablePowerModes: const [],
    hybridModeEnabled: null,
    onPowerSupply: null,
    recommendedFanPreset: null,
  );

  final SystemStatus status;
  final List<String> availablePowerModes;
  final bool? hybridModeEnabled;
  final bool? onPowerSupply;
  final String? recommendedFanPreset;

  @override
  List<Object?> get props => [
    status,
    availablePowerModes,
    hybridModeEnabled,
    onPowerSupply,
    recommendedFanPreset,
  ];
}
