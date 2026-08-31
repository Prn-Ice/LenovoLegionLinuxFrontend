import 'package:equatable/equatable.dart';

import 'dgpu_process.dart';
import 'graphics_mode.dart';

class DgpuSnapshot extends Equatable {
  const DgpuSnapshot({
    required this.isActive,
    required this.processes,
    required this.pciAddress,
    required this.graphicsModeStatus,
    this.name,
  });

  /// null = GPU sysfs path not found (not available / not NVIDIA)
  final bool? isActive;

  /// Empty if nvidia-smi is not installed or reports no processes.
  final List<DgpuProcess> processes;

  /// The discovered PCI address (e.g. "0000:01:00.0"), or null if not found.
  final String? pciAddress;

  /// Authoritative combined policy and observed topology, when supported.
  final GraphicsModeStatus? graphicsModeStatus;
  final String? name;

  @override
  List<Object?> get props => [
    isActive,
    processes,
    pciAddress,
    graphicsModeStatus,
    name,
  ];
}
