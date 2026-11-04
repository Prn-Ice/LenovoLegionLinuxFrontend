import 'package:equatable/equatable.dart';

class DevicesSnapshot extends Equatable {
  const DevicesSnapshot({
    required this.touchpadEnabled,
    required this.touchpadSupported,
    required this.winKeyEnabled,
    required this.winKeySupported,
    required this.fnLockEnabled,
    required this.fnLockSupported,
    required this.cameraEnabled,
    required this.cameraSupported,
    this.cameraWriteSupported = false,
  });

  final bool? touchpadEnabled;
  final bool touchpadSupported;
  final bool? winKeyEnabled;
  final bool winKeySupported;
  final bool? fnLockEnabled;
  final bool fnLockSupported;
  final bool? cameraEnabled;
  final bool cameraSupported;

  /// Camera power can be read from sysfs, but the control service does not
  /// currently expose a write operation for it.
  final bool cameraWriteSupported;

  @override
  List<Object?> get props => [
    touchpadEnabled,
    touchpadSupported,
    winKeyEnabled,
    winKeySupported,
    fnLockEnabled,
    fnLockSupported,
    cameraEnabled,
    cameraSupported,
    cameraWriteSupported,
  ];
}
