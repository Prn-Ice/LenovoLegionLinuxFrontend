import 'package:equatable/equatable.dart';

class DeviceIdentitySnapshot extends Equatable {
  const DeviceIdentitySnapshot({
    required this.productFamily,
    required this.productName,
    required this.serial,
    required this.biosVersion,
  });

  factory DeviceIdentitySnapshot.initial() => const DeviceIdentitySnapshot(
    productFamily: null,
    productName: null,
    serial: null,
    biosVersion: null,
  );

  final String? productFamily;
  final String? productName;
  final String? serial;
  final String? biosVersion;

  String get displayName {
    final family = productFamily?.trim();
    final name = productName?.trim();
    if (family == null && name == null) return 'Unknown Device';
    if (family == null) return name!;
    if (name == null) return family;
    return '$family $name';
  }

  @override
  List<Object?> get props => [productFamily, productName, serial, biosVersion];
}
