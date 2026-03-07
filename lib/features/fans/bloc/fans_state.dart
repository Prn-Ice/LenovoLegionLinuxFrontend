import 'package:equatable/equatable.dart';

import '../models/fan_curve.dart';

class FansState extends Equatable {
  const FansState({
    required this.platformProfile,
    required this.onPowerSupply,
    required this.recommendedPreset,
    required this.availablePresets,
    required this.selectedPreset,
    required this.miniFanCurveEnabled,
    required this.lockFanControllerEnabled,
    required this.maximumFanSpeedEnabled,
    required this.fanCurve,
    required this.fanCurveDirty,
    required this.isLoading,
    required this.isApplying,
    required this.errorMessage,
    required this.noticeMessage,
  });

  factory FansState.initial() => const FansState(
    platformProfile: null,
    onPowerSupply: null,
    recommendedPreset: null,
    availablePresets: [],
    selectedPreset: null,
    miniFanCurveEnabled: null,
    lockFanControllerEnabled: null,
    maximumFanSpeedEnabled: null,
    fanCurve: null,
    fanCurveDirty: false,
    isLoading: false,
    isApplying: false,
    errorMessage: null,
    noticeMessage: null,
  );

  static const _unset = Object();

  final String? platformProfile;
  final bool? onPowerSupply;
  final String? recommendedPreset;
  final List<String> availablePresets;
  final String? selectedPreset;
  final bool? miniFanCurveEnabled;
  final bool? lockFanControllerEnabled;
  final bool? maximumFanSpeedEnabled;
  final FanCurve? fanCurve;
  final bool fanCurveDirty;
  final bool isLoading;
  final bool isApplying;
  final String? errorMessage;
  final String? noticeMessage;

  bool get hasLoaded =>
      platformProfile != null ||
      recommendedPreset != null ||
      availablePresets.isNotEmpty ||
      miniFanCurveEnabled != null ||
      lockFanControllerEnabled != null ||
      maximumFanSpeedEnabled != null ||
      fanCurve != null;

  FansState copyWith({
    Object? platformProfile = _unset,
    Object? onPowerSupply = _unset,
    Object? recommendedPreset = _unset,
    List<String>? availablePresets,
    Object? selectedPreset = _unset,
    Object? miniFanCurveEnabled = _unset,
    Object? lockFanControllerEnabled = _unset,
    Object? maximumFanSpeedEnabled = _unset,
    Object? fanCurve = _unset,
    bool? fanCurveDirty,
    bool? isLoading,
    bool? isApplying,
    Object? errorMessage = _unset,
    Object? noticeMessage = _unset,
  }) {
    return FansState(
      platformProfile: platformProfile == _unset
          ? this.platformProfile
          : platformProfile as String?,
      onPowerSupply: onPowerSupply == _unset
          ? this.onPowerSupply
          : onPowerSupply as bool?,
      recommendedPreset: recommendedPreset == _unset
          ? this.recommendedPreset
          : recommendedPreset as String?,
      availablePresets: availablePresets ?? this.availablePresets,
      selectedPreset: selectedPreset == _unset
          ? this.selectedPreset
          : selectedPreset as String?,
      miniFanCurveEnabled: miniFanCurveEnabled == _unset
          ? this.miniFanCurveEnabled
          : miniFanCurveEnabled as bool?,
      lockFanControllerEnabled: lockFanControllerEnabled == _unset
          ? this.lockFanControllerEnabled
          : lockFanControllerEnabled as bool?,
      maximumFanSpeedEnabled: maximumFanSpeedEnabled == _unset
          ? this.maximumFanSpeedEnabled
          : maximumFanSpeedEnabled as bool?,
      fanCurve: fanCurve == _unset ? this.fanCurve : fanCurve as FanCurve?,
      fanCurveDirty: fanCurveDirty ?? this.fanCurveDirty,
      isLoading: isLoading ?? this.isLoading,
      isApplying: isApplying ?? this.isApplying,
      errorMessage: errorMessage == _unset
          ? this.errorMessage
          : errorMessage as String?,
      noticeMessage: noticeMessage == _unset
          ? this.noticeMessage
          : noticeMessage as String?,
    );
  }

  @override
  List<Object?> get props => [
    platformProfile,
    onPowerSupply,
    recommendedPreset,
    availablePresets,
    selectedPreset,
    miniFanCurveEnabled,
    lockFanControllerEnabled,
    maximumFanSpeedEnabled,
    fanCurve,
    fanCurveDirty,
    isLoading,
    isApplying,
    errorMessage,
    noticeMessage,
  ];
}
