import 'package:equatable/equatable.dart';

class FansSnapshot extends Equatable {
  const FansSnapshot({
    required this.platformProfile,
    required this.onPowerSupply,
    required this.recommendedPreset,
    required this.availablePresets,
    required this.miniFanCurveEnabled,
    required this.lockFanControllerEnabled,
    required this.maximumFanSpeedEnabled,
  });

  final String? platformProfile;
  final bool? onPowerSupply;
  final String? recommendedPreset;
  final List<String> availablePresets;
  final bool? miniFanCurveEnabled;
  final bool? lockFanControllerEnabled;
  final bool? maximumFanSpeedEnabled;

  @override
  List<Object?> get props => [
    platformProfile,
    onPowerSupply,
    recommendedPreset,
    availablePresets,
    miniFanCurveEnabled,
    lockFanControllerEnabled,
    maximumFanSpeedEnabled,
  ];
}
