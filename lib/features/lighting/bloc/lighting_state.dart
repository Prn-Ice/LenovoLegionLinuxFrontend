import 'package:equatable/equatable.dart';

class LightingState extends Equatable {
  const LightingState({
    required this.whiteKeyboardBacklightEnabled,
    required this.whiteKeyboardBacklightSupported,
    required this.yLogoLightEnabled,
    required this.yLogoLightSupported,
    required this.ioPortLightEnabled,
    required this.ioPortLightSupported,
    required this.isLoading,
    this.isApplying = false,
    this.errorMessage,
    this.noticeMessage,
  });

  factory LightingState.initial() => const LightingState(
    whiteKeyboardBacklightEnabled: null,
    whiteKeyboardBacklightSupported: false,
    yLogoLightEnabled: null,
    yLogoLightSupported: false,
    ioPortLightEnabled: null,
    ioPortLightSupported: false,
    isLoading: false,
    isApplying: false,
    errorMessage: null,
    noticeMessage: null,
  );

  static const _unset = Object();

  final bool? whiteKeyboardBacklightEnabled;
  final bool whiteKeyboardBacklightSupported;
  final bool? yLogoLightEnabled;
  final bool yLogoLightSupported;
  final bool? ioPortLightEnabled;
  final bool ioPortLightSupported;
  final bool isLoading;
  final bool isApplying;
  final String? errorMessage;
  final String? noticeMessage;

  bool get hasLoaded =>
      whiteKeyboardBacklightEnabled != null ||
      whiteKeyboardBacklightSupported ||
      yLogoLightEnabled != null ||
      yLogoLightSupported ||
      ioPortLightEnabled != null ||
      ioPortLightSupported;

  LightingState copyWith({
    Object? whiteKeyboardBacklightEnabled = _unset,
    bool? whiteKeyboardBacklightSupported,
    Object? yLogoLightEnabled = _unset,
    bool? yLogoLightSupported,
    Object? ioPortLightEnabled = _unset,
    bool? ioPortLightSupported,
    bool? isLoading,
    bool? isApplying,
    Object? errorMessage = _unset,
    Object? noticeMessage = _unset,
  }) {
    return LightingState(
      whiteKeyboardBacklightEnabled: whiteKeyboardBacklightEnabled == _unset
          ? this.whiteKeyboardBacklightEnabled
          : whiteKeyboardBacklightEnabled as bool?,
      whiteKeyboardBacklightSupported:
          whiteKeyboardBacklightSupported ?? this.whiteKeyboardBacklightSupported,
      yLogoLightEnabled: yLogoLightEnabled == _unset
          ? this.yLogoLightEnabled
          : yLogoLightEnabled as bool?,
      yLogoLightSupported: yLogoLightSupported ?? this.yLogoLightSupported,
      ioPortLightEnabled: ioPortLightEnabled == _unset
          ? this.ioPortLightEnabled
          : ioPortLightEnabled as bool?,
      ioPortLightSupported: ioPortLightSupported ?? this.ioPortLightSupported,
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
    whiteKeyboardBacklightEnabled,
    whiteKeyboardBacklightSupported,
    yLogoLightEnabled,
    yLogoLightSupported,
    ioPortLightEnabled,
    ioPortLightSupported,
    isLoading,
    isApplying,
    errorMessage,
    noticeMessage,
  ];
}
