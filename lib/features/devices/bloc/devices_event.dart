import 'package:equatable/equatable.dart';

sealed class DevicesEvent extends Equatable {
  const DevicesEvent();

  @override
  List<Object?> get props => const [];
}

final class DevicesStarted extends DevicesEvent {
  const DevicesStarted();
}

final class DevicesRefreshRequested extends DevicesEvent {
  const DevicesRefreshRequested();
}

final class DevicesTicked extends DevicesEvent {
  const DevicesTicked();
}

final class TouchpadSetRequested extends DevicesEvent {
  const TouchpadSetRequested(this.enabled);

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}

final class WinKeySetRequested extends DevicesEvent {
  const WinKeySetRequested(this.enabled);

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}

final class FnLockSetRequested extends DevicesEvent {
  const FnLockSetRequested(this.enabled);

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}

final class AlwaysOnUsbSetRequested extends DevicesEvent {
  const AlwaysOnUsbSetRequested(this.enabled);

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}

final class CameraSetRequested extends DevicesEvent {
  const CameraSetRequested(this.enabled);

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}
