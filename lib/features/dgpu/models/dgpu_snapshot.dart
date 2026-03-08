import 'dgpu_process.dart';

class DgpuSnapshot {
  const DgpuSnapshot({
    required this.isActive,
    required this.processes,
    required this.pciAddress,
  });

  /// null = GPU sysfs path not found (not available / not NVIDIA)
  final bool? isActive;

  /// Empty if nvidia-smi is not installed or reports no processes.
  final List<DgpuProcess> processes;

  /// The discovered PCI address (e.g. "0000:01:00.0"), or null if not found.
  final String? pciAddress;
}
