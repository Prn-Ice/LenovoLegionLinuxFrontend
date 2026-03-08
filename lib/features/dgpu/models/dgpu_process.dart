import 'package:equatable/equatable.dart';

class DgpuProcess extends Equatable {
  const DgpuProcess({
    required this.pid,
    required this.name,
    required this.usedMemoryMib,
  });

  final int pid;
  final String name;
  final int usedMemoryMib;

  /// Parses output of:
  /// nvidia-smi --query-compute-apps=pid,process_name,used_gpu_memory
  ///            --format=csv,noheader,nounits
  ///
  /// Each line: "<pid>, <process_name>, <used_memory_MiB>"
  static List<DgpuProcess> parseNvidiaSmiOutput(String output) {
    final processes = <DgpuProcess>[];
    for (final line in output.trim().split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final parts = trimmed.split(',');
      if (parts.length < 3) continue;
      final pid = int.tryParse(parts[0].trim());
      if (pid == null) continue;
      final rawName = parts[1].trim();
      final name = rawName.contains('/') ? rawName.split('/').last : rawName;
      final mem = int.tryParse(parts[2].trim()) ?? 0;
      processes.add(DgpuProcess(pid: pid, name: name, usedMemoryMib: mem));
    }
    return processes;
  }

  @override
  List<Object?> get props => [pid, name, usedMemoryMib];
}
