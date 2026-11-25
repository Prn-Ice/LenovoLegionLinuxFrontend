import 'package:equatable/equatable.dart';

import 'gpu_process.dart';

/// Which processes the kernel attributes to one GPU.
///
/// The kernel reports DRM client statistics through `/proc/<pid>/fdinfo`.
/// A client's GPU is identified by `drm-pdev`; kernels and drivers that do
/// not publish that field cannot attribute a process to a specific GPU.
class GpuProcessScan extends Equatable {
  const GpuProcessScan({required this.processes, required this.reporting});

  static const noClients = GpuProcessScan(
    processes: [],
    reporting: GpuProcessReporting.noClients,
  );

  static const notReported = GpuProcessScan(
    processes: [],
    reporting: GpuProcessReporting.notReported,
  );

  final List<GpuProcess> processes;
  final GpuProcessReporting reporting;

  @override
  List<Object?> get props => [processes, reporting];
}

enum GpuProcessReporting {
  /// The kernel names the GPU for at least one readable DRM client.
  reported,

  /// Readable DRM clients exist, but their GPU is not named.
  notReported,

  /// No readable process holds a DRM client.
  noClients,
}
