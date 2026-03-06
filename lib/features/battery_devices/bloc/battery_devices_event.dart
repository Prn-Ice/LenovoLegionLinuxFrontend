import 'package:equatable/equatable.dart';

sealed class BatteryDevicesEvent extends Equatable {
  const BatteryDevicesEvent();

  @override
  List<Object?> get props => const [];
}

final class BatteryDevicesStarted extends BatteryDevicesEvent {
  const BatteryDevicesStarted();
}

final class BatteryDevicesRefreshRequested extends BatteryDevicesEvent {
  const BatteryDevicesRefreshRequested();
}

final class BatteryConservationSetRequested extends BatteryDevicesEvent {
  const BatteryConservationSetRequested(this.enabled);

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}

final class RapidChargingSetRequested extends BatteryDevicesEvent {
  const RapidChargingSetRequested(this.enabled);

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}

final class AlwaysOnUsbChargingSetRequested extends BatteryDevicesEvent {
  const AlwaysOnUsbChargingSetRequested(this.enabled);

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}

final class TouchpadSetRequested extends BatteryDevicesEvent {
  const TouchpadSetRequested(this.enabled);

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}

final class WinKeySetRequested extends BatteryDevicesEvent {
  const WinKeySetRequested(this.enabled);

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}

final class FnLockSetRequested extends BatteryDevicesEvent {
  const FnLockSetRequested(this.enabled);

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}
