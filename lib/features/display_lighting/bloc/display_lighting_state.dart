import 'package:equatable/equatable.dart';

class DisplayLightingState extends Equatable {
  const DisplayLightingState({
    required this.hybridModeEnabled,
    required this.hybridModeSupported,
    required this.overdriveEnabled,
    required this.overdriveSupported,
    required this.isLoading,
    required this.isApplying,
    required this.errorMessage,
    required this.noticeMessage,
  });

  factory DisplayLightingState.initial() => const DisplayLightingState(
    hybridModeEnabled: null,
    hybridModeSupported: false,
    overdriveEnabled: null,
    overdriveSupported: false,
    isLoading: false,
    isApplying: false,
    errorMessage: null,
    noticeMessage: null,
  );

  static const _unset = Object();

  final bool? hybridModeEnabled;
  final bool hybridModeSupported;
  final bool? overdriveEnabled;
  final bool overdriveSupported;
  final bool isLoading;
  final bool isApplying;
  final String? errorMessage;
  final String? noticeMessage;

  bool get hasLoaded =>
      hybridModeEnabled != null ||
      hybridModeSupported ||
      overdriveEnabled != null ||
      overdriveSupported;

  DisplayLightingState copyWith({
    Object? hybridModeEnabled = _unset,
    bool? hybridModeSupported,
    Object? overdriveEnabled = _unset,
    bool? overdriveSupported,
    bool? isLoading,
    bool? isApplying,
    Object? errorMessage = _unset,
    Object? noticeMessage = _unset,
  }) {
    return DisplayLightingState(
      hybridModeEnabled: hybridModeEnabled == _unset
          ? this.hybridModeEnabled
          : hybridModeEnabled as bool?,
      hybridModeSupported: hybridModeSupported ?? this.hybridModeSupported,
      overdriveEnabled: overdriveEnabled == _unset
          ? this.overdriveEnabled
          : overdriveEnabled as bool?,
      overdriveSupported: overdriveSupported ?? this.overdriveSupported,
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
    hybridModeEnabled,
    hybridModeSupported,
    overdriveEnabled,
    overdriveSupported,
    isLoading,
    isApplying,
    errorMessage,
    noticeMessage,
  ];
}
