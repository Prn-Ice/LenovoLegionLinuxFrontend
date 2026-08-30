import 'package:equatable/equatable.dart';

sealed class BatteryEvent extends Equatable {
  const BatteryEvent();

  @override
  List<Object?> get props => const [];
}

final class BatteryStarted extends BatteryEvent {
  const BatteryStarted();
}

final class BatteryRefreshRequested extends BatteryEvent {
  const BatteryRefreshRequested();
}

final class BatteryTicked extends BatteryEvent {
  const BatteryTicked();
}

final class BatteryConservationSetRequested extends BatteryEvent {
  const BatteryConservationSetRequested(this.enabled);

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}

final class RapidChargingSetRequested extends BatteryEvent {
  const RapidChargingSetRequested(this.enabled);

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}

final class AlwaysOnUsbSetRequested extends BatteryEvent {
  const AlwaysOnUsbSetRequested(this.enabled);

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}
