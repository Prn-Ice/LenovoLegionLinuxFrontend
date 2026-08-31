import 'package:equatable/equatable.dart';

import '../models/dgpu_process.dart';
import '../models/graphics_mode.dart';

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
    required this.graphicsModeStatus,
    required this.applyingGraphicsMode,
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
    graphicsModeStatus: null,
    applyingGraphicsMode: null,
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

  final GraphicsModeStatus? graphicsModeStatus;
  final GraphicsMode? applyingGraphicsMode;
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
    Object? graphicsModeStatus = _unset,
    Object? applyingGraphicsMode = _unset,
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
      graphicsModeStatus: graphicsModeStatus == _unset
          ? this.graphicsModeStatus
          : graphicsModeStatus as GraphicsModeStatus?,
      applyingGraphicsMode: applyingGraphicsMode == _unset
          ? this.applyingGraphicsMode
          : applyingGraphicsMode as GraphicsMode?,
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
    graphicsModeStatus,
    applyingGraphicsMode,
    name,
  ];
}
