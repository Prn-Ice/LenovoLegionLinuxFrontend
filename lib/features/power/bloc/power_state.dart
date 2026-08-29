import 'package:equatable/equatable.dart';

import '../../../core/models/cpu_policy_snapshot.dart';
import '../../../core/models/power_profiles_daemon_snapshot.dart';
import '../models/power_limit.dart';
import '../models/power_mode.dart';

class PowerState extends Equatable {
  const PowerState({
    required this.currentMode,
    required this.availableModes,
    required this.powerLimits,
    required this.cpuOverclockEnabled,
    required this.gpuOverclockEnabled,
    required this.onPowerSupply,
    required this.daemonSnapshot,
    required this.cpuPolicy,
    required this.isLoading,
    required this.isApplying,
    required this.errorMessage,
    required this.noticeMessage,
  });

  factory PowerState.initial() => const PowerState(
    currentMode: null,
    availableModes: [],
    powerLimits: [],
    cpuOverclockEnabled: null,
    gpuOverclockEnabled: null,
    onPowerSupply: null,
    daemonSnapshot: null,
    cpuPolicy: null,
    isLoading: false,
    isApplying: false,
    errorMessage: null,
    noticeMessage: null,
  );

  static const _unset = Object();

  final PowerMode? currentMode;
  final List<PowerMode> availableModes;
  final List<PowerLimitReading> powerLimits;
  final bool? cpuOverclockEnabled;
  final bool? gpuOverclockEnabled;
  final bool? onPowerSupply;
  final PowerProfilesDaemonSnapshot? daemonSnapshot;
  final CpuPolicySnapshot? cpuPolicy;
  final bool isLoading;
  final bool isApplying;
  final String? errorMessage;
  final String? noticeMessage;

  bool get hasLoaded =>
      currentMode != null ||
      availableModes.isNotEmpty ||
      powerLimits.isNotEmpty ||
      cpuOverclockEnabled != null ||
      gpuOverclockEnabled != null ||
      onPowerSupply != null ||
      daemonSnapshot != null ||
      cpuPolicy != null;

  PowerState copyWith({
    Object? currentMode = _unset,
    List<PowerMode>? availableModes,
    List<PowerLimitReading>? powerLimits,
    Object? cpuOverclockEnabled = _unset,
    Object? gpuOverclockEnabled = _unset,
    Object? onPowerSupply = _unset,
    Object? daemonSnapshot = _unset,
    Object? cpuPolicy = _unset,
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
      cpuOverclockEnabled: cpuOverclockEnabled == _unset
          ? this.cpuOverclockEnabled
          : cpuOverclockEnabled as bool?,
      gpuOverclockEnabled: gpuOverclockEnabled == _unset
          ? this.gpuOverclockEnabled
          : gpuOverclockEnabled as bool?,
      onPowerSupply: onPowerSupply == _unset
          ? this.onPowerSupply
          : onPowerSupply as bool?,
      daemonSnapshot: daemonSnapshot == _unset
          ? this.daemonSnapshot
          : daemonSnapshot as PowerProfilesDaemonSnapshot?,
      cpuPolicy: cpuPolicy == _unset
          ? this.cpuPolicy
          : cpuPolicy as CpuPolicySnapshot?,
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
    cpuOverclockEnabled,
    gpuOverclockEnabled,
    onPowerSupply,
    daemonSnapshot,
    cpuPolicy,
    isLoading,
    isApplying,
    errorMessage,
    noticeMessage,
  ];
}
