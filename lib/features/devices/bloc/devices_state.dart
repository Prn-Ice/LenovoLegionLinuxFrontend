import 'package:equatable/equatable.dart';

class DevicesState extends Equatable {
  const DevicesState({
    required this.touchpadEnabled,
    required this.touchpadSupported,
    required this.winKeyEnabled,
    required this.winKeySupported,
    required this.fnLockEnabled,
    required this.fnLockSupported,
    required this.cameraEnabled,
    required this.cameraSupported,
    required this.isLoading,
    required this.isApplying,
    required this.errorMessage,
    required this.noticeMessage,
  });

  factory DevicesState.initial() => const DevicesState(
    touchpadEnabled: null,
    touchpadSupported: false,
    winKeyEnabled: null,
    winKeySupported: false,
    fnLockEnabled: null,
    fnLockSupported: false,
    cameraEnabled: null,
    cameraSupported: false,
    isLoading: false,
    isApplying: false,
    errorMessage: null,
    noticeMessage: null,
  );

  static const _unset = Object();

  final bool? touchpadEnabled;
  final bool touchpadSupported;
  final bool? winKeyEnabled;
  final bool winKeySupported;
  final bool? fnLockEnabled;
  final bool fnLockSupported;
  final bool? cameraEnabled;
  final bool cameraSupported;
  final bool isLoading;
  final bool isApplying;
  final String? errorMessage;
  final String? noticeMessage;

  bool get hasLoaded =>
      touchpadEnabled != null ||
      winKeyEnabled != null ||
      fnLockEnabled != null ||
      cameraEnabled != null;

  DevicesState copyWith({
    Object? touchpadEnabled = _unset,
    bool? touchpadSupported,
    Object? winKeyEnabled = _unset,
    bool? winKeySupported,
    Object? fnLockEnabled = _unset,
    bool? fnLockSupported,
    Object? cameraEnabled = _unset,
    bool? cameraSupported,
    bool? isLoading,
    bool? isApplying,
    Object? errorMessage = _unset,
    Object? noticeMessage = _unset,
  }) {
    return DevicesState(
      touchpadEnabled: touchpadEnabled == _unset
          ? this.touchpadEnabled
          : touchpadEnabled as bool?,
      touchpadSupported: touchpadSupported ?? this.touchpadSupported,
      winKeyEnabled: winKeyEnabled == _unset
          ? this.winKeyEnabled
          : winKeyEnabled as bool?,
      winKeySupported: winKeySupported ?? this.winKeySupported,
      fnLockEnabled: fnLockEnabled == _unset
          ? this.fnLockEnabled
          : fnLockEnabled as bool?,
      fnLockSupported: fnLockSupported ?? this.fnLockSupported,
      cameraEnabled: cameraEnabled == _unset
          ? this.cameraEnabled
          : cameraEnabled as bool?,
      cameraSupported: cameraSupported ?? this.cameraSupported,
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
    touchpadEnabled,
    touchpadSupported,
    winKeyEnabled,
    winKeySupported,
    fnLockEnabled,
    fnLockSupported,
    cameraEnabled,
    cameraSupported,
    isLoading,
    isApplying,
    errorMessage,
    noticeMessage,
  ];
}
