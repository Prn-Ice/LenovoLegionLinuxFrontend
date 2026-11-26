import 'package:equatable/equatable.dart';

import '../../../core/models/app_failure.dart';
import '../../../core/models/gpu_process_scan.dart';
import '../models/graphics_mode.dart';

class DgpuState extends Equatable {
  const DgpuState({
    required this.isActive,
    required this.processScan,
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
    processScan: null,
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
  final GpuProcessScan? processScan;
  final String? pciAddress;
  final bool isLoading;
  final bool isApplying;
  final bool hasLoaded;
  final AppFailure? errorMessage;
  final String? noticeMessage;

  final GraphicsModeStatus? graphicsModeStatus;
  final GraphicsMode? applyingGraphicsMode;
  final String? name;

  /// true when the GPU sysfs entry was found (even if suspended)
  bool get isAvailable => isActive != null;

  DgpuState copyWith({
    Object? isActive = _unset,
    Object? processScan = _unset,
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
      processScan: processScan == _unset
          ? this.processScan
          : processScan as GpuProcessScan?,
      pciAddress: pciAddress == _unset
          ? this.pciAddress
          : pciAddress as String?,
      isLoading: isLoading ?? this.isLoading,
      isApplying: isApplying ?? this.isApplying,
      hasLoaded: hasLoaded ?? this.hasLoaded,
      errorMessage: errorMessage == _unset
          ? this.errorMessage
          : AppFailure.optional(errorMessage),
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
    processScan,
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
