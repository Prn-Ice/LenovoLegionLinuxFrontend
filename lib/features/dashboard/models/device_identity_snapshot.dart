import 'package:equatable/equatable.dart';

class DeviceIdentitySnapshot extends Equatable {
  const DeviceIdentitySnapshot({
    required this.productFamily,
    required this.productName,
    required this.serial,
    required this.biosVersion,
    this.cpuName,
    this.kernelRelease,
    this.legionModuleVersion,
    this.uptimeSeconds,
  });

  factory DeviceIdentitySnapshot.initial() => const DeviceIdentitySnapshot(
    productFamily: null,
    productName: null,
    serial: null,
    biosVersion: null,
    cpuName: null,
    kernelRelease: null,
    legionModuleVersion: null,
    uptimeSeconds: null,
  );

  final String? productFamily;
  final String? productName;
  final String? serial;
  final String? biosVersion;
  final String? cpuName;
  final String? kernelRelease;
  final String? legionModuleVersion;
  final int? uptimeSeconds;

  String get displayName {
    final family = productFamily?.trim();
    final name = productName?.trim();
    if (family == null && name == null) return 'Unknown Device';
    if (family == null) return name!;
    if (name == null) return family;
    return '$family $name';
  }

  /// Uptime as a compact `Dd HHh` / `HHh MMm` / `MMm` string, or null.
  String? get uptimeLabel {
    final secs = uptimeSeconds;
    if (secs == null) return null;
    final days = secs ~/ 86400;
    final hours = (secs % 86400) ~/ 3600;
    final minutes = (secs % 3600) ~/ 60;
    if (days > 0) return '${days}d ${hours.toString().padLeft(2, '0')}h';
    if (hours > 0) return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
    return '${minutes}m';
  }

  @override
  List<Object?> get props => [
    productFamily,
    productName,
    serial,
    biosVersion,
    cpuName,
    kernelRelease,
    legionModuleVersion,
    uptimeSeconds,
  ];
}
