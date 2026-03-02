import 'package:equatable/equatable.dart';

import '../models/power_limit.dart';
import '../models/power_mode.dart';

class PowerState extends Equatable {
  const PowerState({
    required this.currentMode,
    required this.availableModes,
    required this.powerLimits,
    required this.isLoading,
    required this.isApplying,
    required this.errorMessage,
    required this.noticeMessage,
  });

  factory PowerState.initial() => const PowerState(
    currentMode: null,
    availableModes: [],
    powerLimits: [],
    isLoading: false,
    isApplying: false,
    errorMessage: null,
    noticeMessage: null,
  );

  static const _unset = Object();

  final PowerMode? currentMode;
  final List<PowerMode> availableModes;
  final List<PowerLimitReading> powerLimits;
  final bool isLoading;
  final bool isApplying;
  final String? errorMessage;
  final String? noticeMessage;

  bool get hasLoaded =>
      currentMode != null ||
      availableModes.isNotEmpty ||
      powerLimits.isNotEmpty;

  PowerState copyWith({
    Object? currentMode = _unset,
    List<PowerMode>? availableModes,
    List<PowerLimitReading>? powerLimits,
    bool? isLoading,
    bool? isApplying,
    Object? errorMessage = _unset,
    Object? noticeMessage = _unset,
  }) {
    return PowerState(
      currentMode: currentMode == _unset
          ? this.currentMode
          : currentMode as PowerMode?,
      availableModes: availableModes ?? this.availableModes,
      powerLimits: powerLimits ?? this.powerLimits,
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
    currentMode,
    availableModes,
    powerLimits,
    isLoading,
    isApplying,
    errorMessage,
    noticeMessage,
  ];
}
