import 'package:equatable/equatable.dart';

class DisplayLightingState extends Equatable {
  const DisplayLightingState({
    required this.hybridModeEnabled,
    required this.hybridModeSupported,
    required this.overdriveEnabled,
    required this.overdriveSupported,
    required this.whiteKeyboardBacklightEnabled,
    required this.whiteKeyboardBacklightSupported,
    required this.yLogoLightEnabled,
    required this.yLogoLightSupported,
    required this.ioPortLightEnabled,
    required this.ioPortLightSupported,
    required this.xrandrOutputName,
    required this.availableRefreshRates,
    required this.currentRefreshRate,
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
    whiteKeyboardBacklightEnabled: null,
    whiteKeyboardBacklightSupported: false,
    yLogoLightEnabled: null,
    yLogoLightSupported: false,
    ioPortLightEnabled: null,
    ioPortLightSupported: false,
    xrandrOutputName: null,
    availableRefreshRates: null,
    currentRefreshRate: null,
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
  final bool? whiteKeyboardBacklightEnabled;
  final bool whiteKeyboardBacklightSupported;
  final bool? yLogoLightEnabled;
  final bool yLogoLightSupported;
  final bool? ioPortLightEnabled;
  final bool ioPortLightSupported;
  final String? xrandrOutputName;
  final List<double>? availableRefreshRates;
  final double? currentRefreshRate;
  final bool isLoading;
  final bool isApplying;
  final String? errorMessage;
  final String? noticeMessage;

  bool get hasLoaded =>
      hybridModeEnabled != null ||
      hybridModeSupported ||
      overdriveEnabled != null ||
      overdriveSupported ||
      whiteKeyboardBacklightEnabled != null ||
      whiteKeyboardBacklightSupported ||
      yLogoLightEnabled != null ||
      yLogoLightSupported ||
      ioPortLightEnabled != null ||
      ioPortLightSupported;

  DisplayLightingState copyWith({
    Object? hybridModeEnabled = _unset,
    bool? hybridModeSupported,
    Object? overdriveEnabled = _unset,
    bool? overdriveSupported,
    Object? whiteKeyboardBacklightEnabled = _unset,
    bool? whiteKeyboardBacklightSupported,
    Object? yLogoLightEnabled = _unset,
    bool? yLogoLightSupported,
    Object? ioPortLightEnabled = _unset,
    bool? ioPortLightSupported,
    Object? xrandrOutputName = _unset,
    Object? availableRefreshRates = _unset,
    Object? currentRefreshRate = _unset,
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
      whiteKeyboardBacklightEnabled: whiteKeyboardBacklightEnabled == _unset
          ? this.whiteKeyboardBacklightEnabled
          : whiteKeyboardBacklightEnabled as bool?,
      whiteKeyboardBacklightSupported:
          whiteKeyboardBacklightSupported ??
          this.whiteKeyboardBacklightSupported,
      yLogoLightEnabled: yLogoLightEnabled == _unset
          ? this.yLogoLightEnabled
          : yLogoLightEnabled as bool?,
      yLogoLightSupported: yLogoLightSupported ?? this.yLogoLightSupported,
      ioPortLightEnabled: ioPortLightEnabled == _unset
          ? this.ioPortLightEnabled
          : ioPortLightEnabled as bool?,
      ioPortLightSupported: ioPortLightSupported ?? this.ioPortLightSupported,
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
    hybridModeEnabled,
    hybridModeSupported,
    overdriveEnabled,
    overdriveSupported,
    whiteKeyboardBacklightEnabled,
    whiteKeyboardBacklightSupported,
    yLogoLightEnabled,
    yLogoLightSupported,
    ioPortLightEnabled,
    ioPortLightSupported,
    xrandrOutputName,
    availableRefreshRates,
    currentRefreshRate,
    isLoading,
    isApplying,
    errorMessage,
    noticeMessage,
  ];
}
