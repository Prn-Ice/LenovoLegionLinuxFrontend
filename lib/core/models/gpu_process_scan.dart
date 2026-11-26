import 'package:equatable/equatable.dart';

import 'gpu_process.dart';

/// The processes procfs associates with one GPU through device links or DRM statistics.
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
  /// At least one readable client has an identifiable GPU.
  reported,

  /// Readable DRM clients exist, but their GPU is not named.
  notReported,

  /// No readable process holds a matching device.
  noClients,
}
