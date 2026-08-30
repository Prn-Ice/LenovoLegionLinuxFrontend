import 'package:equatable/equatable.dart';

import '../models/dgpu_process.dart';

class DgpuState extends Equatable {
  const DgpuState({
    required this.isActive,
    required this.processes,
    required this.pciAddress,
    required this.isLoading,
    required this.isApplying,
    required this.hasLoaded,
    required this.errorMessage,
    required this.noticeMessage,
    required this.hybridModeEnabled,
    required this.hybridModeSupported,
    required this.name,
  });

  factory DgpuState.initial() => const DgpuState(
    isActive: null,
    processes: [],
    pciAddress: null,
    isLoading: false,
    isApplying: false,
    hasLoaded: false,
    errorMessage: null,
    noticeMessage: null,
    hybridModeEnabled: null,
    hybridModeSupported: false,
    name: null,
  );

  static const _unset = Object();

  /// null = sysfs runtime_status path not found (NVIDIA GPU unavailable)
  final bool? isActive;
  final List<DgpuProcess> processes;
  final String? pciAddress;
  final bool isLoading;
  final bool isApplying;
  final bool hasLoaded;
  final String? errorMessage;
  final String? noticeMessage;

  /// null if hybrid mode sysfs file is not present (unsupported).
  final bool? hybridModeEnabled;

  /// true when the hybrid mode sysfs file was found.
  final bool hybridModeSupported;
  final String? name;

  /// true when the GPU sysfs entry was found (even if suspended)
  bool get isAvailable => isActive != null;

  DgpuState copyWith({
    Object? isActive = _unset,
    List<DgpuProcess>? processes,
    Object? pciAddress = _unset,
    bool? isLoading,
    bool? isApplying,
    bool? hasLoaded,
    Object? errorMessage = _unset,
    Object? noticeMessage = _unset,
    Object? hybridModeEnabled = _unset,
    bool? hybridModeSupported,
    Object? name = _unset,
  }) {
    return DgpuState(
      isActive: isActive == _unset ? this.isActive : isActive as bool?,
      processes: processes ?? this.processes,
      pciAddress: pciAddress == _unset
          ? this.pciAddress
          : pciAddress as String?,
      isLoading: isLoading ?? this.isLoading,
      isApplying: isApplying ?? this.isApplying,
      hasLoaded: hasLoaded ?? this.hasLoaded,
      errorMessage: errorMessage == _unset
          ? this.errorMessage
          : errorMessage as String?,
      noticeMessage: noticeMessage == _unset
          ? this.noticeMessage
          : noticeMessage as String?,
      hybridModeEnabled: hybridModeEnabled == _unset
          ? this.hybridModeEnabled
          : hybridModeEnabled as bool?,
      hybridModeSupported: hybridModeSupported ?? this.hybridModeSupported,
      name: name == _unset ? this.name : name as String?,
    );
  }

  @override
  List<Object?> get props => [
    isActive,
    processes,
    pciAddress,
    isLoading,
    isApplying,
    hasLoaded,
    errorMessage,
    noticeMessage,
    hybridModeEnabled,
    hybridModeSupported,
    name,
  ];
}
