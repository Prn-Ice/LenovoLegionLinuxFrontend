import 'package:equatable/equatable.dart';

import '../models/dgpu_process.dart';

class DgpuState extends Equatable {
  const DgpuState({
    required this.isActive,
    required this.processes,
    required this.pciAddress,
    required this.isLoading,
    required this.isApplying,
    required this.errorMessage,
    required this.noticeMessage,
  });

  factory DgpuState.initial() => const DgpuState(
    isActive: null,
    processes: [],
    pciAddress: null,
    isLoading: false,
    isApplying: false,
    errorMessage: null,
    noticeMessage: null,
  );

  static const _unset = Object();

  /// null = sysfs runtime_status path not found (NVIDIA GPU unavailable)
  final bool? isActive;
  final List<DgpuProcess> processes;
  final String? pciAddress;
  final bool isLoading;
  final bool isApplying;
  final String? errorMessage;
  final String? noticeMessage;

  /// true when the GPU sysfs entry was found (even if suspended)
  bool get isAvailable => isActive != null;

  DgpuState copyWith({
    Object? isActive = _unset,
    List<DgpuProcess>? processes,
    Object? pciAddress = _unset,
    bool? isLoading,
    bool? isApplying,
    Object? errorMessage = _unset,
    Object? noticeMessage = _unset,
  }) {
    return DgpuState(
      isActive: isActive == _unset ? this.isActive : isActive as bool?,
      processes: processes ?? this.processes,
      pciAddress: pciAddress == _unset ? this.pciAddress : pciAddress as String?,
      isLoading: isLoading ?? this.isLoading,
      isApplying: isApplying ?? this.isApplying,
      errorMessage:
          errorMessage == _unset ? this.errorMessage : errorMessage as String?,
      noticeMessage:
          noticeMessage == _unset ? this.noticeMessage : noticeMessage as String?,
    );
  }

  @override
  List<Object?> get props => [
    isActive,
    processes,
    pciAddress,
    isLoading,
    isApplying,
    errorMessage,
    noticeMessage,
  ];
}
