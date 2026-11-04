import 'package:equatable/equatable.dart';

import 'device_identity_snapshot.dart';
import 'system_status.dart';

class DashboardSnapshot extends Equatable {
  const DashboardSnapshot({
    required this.status,
    required this.availablePowerModes,
    required this.hybridModeEnabled,
    required this.overdriveEnabled,
    required this.onPowerSupply,
    required this.recommendedFanPreset,
    required this.deviceIdentity,
  });

  factory DashboardSnapshot.initial() => DashboardSnapshot(
    status: SystemStatus.initial(),
    availablePowerModes: const [],
    hybridModeEnabled: null,
    overdriveEnabled: null,
    onPowerSupply: null,
    recommendedFanPreset: null,
    deviceIdentity: DeviceIdentitySnapshot.initial(),
  );

  final SystemStatus status;
  final List<String> availablePowerModes;
  final bool? hybridModeEnabled;
  final bool? overdriveEnabled;
  final bool? onPowerSupply;
  final String? recommendedFanPreset;
  final DeviceIdentitySnapshot deviceIdentity;

  DashboardSnapshot copyWith({
    SystemStatus? status,
    List<String>? availablePowerModes,
    bool? hybridModeEnabled,
    bool? overdriveEnabled,
    bool? onPowerSupply,
    String? recommendedFanPreset,
    DeviceIdentitySnapshot? deviceIdentity,
  }) {
    return DashboardSnapshot(
      status: status ?? this.status,
      availablePowerModes: availablePowerModes ?? this.availablePowerModes,
      hybridModeEnabled: hybridModeEnabled ?? this.hybridModeEnabled,
      overdriveEnabled: overdriveEnabled ?? this.overdriveEnabled,
      onPowerSupply: onPowerSupply ?? this.onPowerSupply,
      recommendedFanPreset: recommendedFanPreset ?? this.recommendedFanPreset,
      deviceIdentity: deviceIdentity ?? this.deviceIdentity,
    );
  }

  @override
  List<Object?> get props => [
    status,
    availablePowerModes,
    hybridModeEnabled,
    overdriveEnabled,
    onPowerSupply,
    recommendedFanPreset,
    deviceIdentity,
  ];
}
