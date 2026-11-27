import 'package:equatable/equatable.dart';

class DgpuSnapshot extends Equatable {
  const DgpuSnapshot({required this.isActive, required this.pciAddress});

  /// null = GPU sysfs path not found (not available / not NVIDIA)
  final bool? isActive;

  /// The discovered PCI address (e.g. "0000:01:00.0"), or null if not found.
  final String? pciAddress;

  @override
  List<Object?> get props => [isActive, pciAddress];
}
