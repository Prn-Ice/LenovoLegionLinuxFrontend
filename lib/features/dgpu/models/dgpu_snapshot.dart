import 'package:equatable/equatable.dart';

import 'dgpu_process.dart';

class DgpuSnapshot extends Equatable {
  const DgpuSnapshot({
    required this.isActive,
    required this.processes,
    required this.pciAddress,
    required this.hybridModeEnabled,
    required this.hybridModeSupported,
  });

  /// null = GPU sysfs path not found (not available / not NVIDIA)
  final bool? isActive;

  /// Empty if nvidia-smi is not installed or reports no processes.
  final List<DgpuProcess> processes;

  /// The discovered PCI address (e.g. "0000:01:00.0"), or null if not found.
  final String? pciAddress;

  /// null if hybrid mode sysfs file is not present (unsupported).
  final bool? hybridModeEnabled;

  /// true when the hybrid mode sysfs file was found.
  final bool hybridModeSupported;

  @override
  List<Object?> get props => [
    isActive,
    processes,
    pciAddress,
    hybridModeEnabled,
    hybridModeSupported,
  ];
}
