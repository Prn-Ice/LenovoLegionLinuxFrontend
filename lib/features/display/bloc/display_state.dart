import 'package:equatable/equatable.dart';

class DisplayState extends Equatable {
  const DisplayState({
    required this.overdriveEnabled,
    required this.overdriveSupported,
    required this.xrandrOutputName,
    required this.availableRefreshRates,
    required this.currentRefreshRate,
    required this.isLoading,
    this.isApplying = false,
    this.errorMessage,
    this.noticeMessage,
  });

  factory DisplayState.initial() => const DisplayState(
    overdriveEnabled: null,
    overdriveSupported: false,
    xrandrOutputName: null,
    availableRefreshRates: null,
    currentRefreshRate: null,
    isLoading: false,
    isApplying: false,
    errorMessage: null,
    noticeMessage: null,
  );

  static const _unset = Object();

  final bool? overdriveEnabled;
  final bool overdriveSupported;
  final String? xrandrOutputName;
  final List<double>? availableRefreshRates;
  final double? currentRefreshRate;
  final bool isLoading;
  final bool isApplying;
  final String? errorMessage;
  final String? noticeMessage;

  bool get hasLoaded =>
      overdriveEnabled != null ||
      overdriveSupported ||
      xrandrOutputName != null;

  DisplayState copyWith({
    Object? overdriveEnabled = _unset,
    bool? overdriveSupported,
    Object? xrandrOutputName = _unset,
    Object? availableRefreshRates = _unset,
    Object? currentRefreshRate = _unset,
    bool? isLoading,
    bool? isApplying,
    Object? errorMessage = _unset,
    Object? noticeMessage = _unset,
  }) {
    return DisplayState(
      overdriveEnabled: overdriveEnabled == _unset
          ? this.overdriveEnabled
          : overdriveEnabled as bool?,
      overdriveSupported: overdriveSupported ?? this.overdriveSupported,
      xrandrOutputName: xrandrOutputName == _unset
          ? this.xrandrOutputName
          : xrandrOutputName as String?,
      availableRefreshRates: availableRefreshRates == _unset
          ? this.availableRefreshRates
          : availableRefreshRates as List<double>?,
      currentRefreshRate: currentRefreshRate == _unset
          ? this.currentRefreshRate
          : currentRefreshRate as double?,
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
    overdriveEnabled,
    overdriveSupported,
    xrandrOutputName,
    availableRefreshRates,
    currentRefreshRate,
    isLoading,
    isApplying,
    errorMessage,
    noticeMessage,
  ];
}
