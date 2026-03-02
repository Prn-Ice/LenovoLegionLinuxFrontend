import 'package:equatable/equatable.dart';

sealed class DashboardEvent extends Equatable {
  const DashboardEvent();

  @override
  List<Object?> get props => const [];
}

final class DashboardStarted extends DashboardEvent {
  const DashboardStarted();
}

final class DashboardRefreshRequested extends DashboardEvent {
  const DashboardRefreshRequested();
}

final class DashboardTicked extends DashboardEvent {
  const DashboardTicked();
}

final class DashboardPowerModeSetRequested extends DashboardEvent {
  const DashboardPowerModeSetRequested(this.mode);

  final String mode;

  @override
  List<Object?> get props => [mode];
}

final class DashboardHybridModeSetRequested extends DashboardEvent {
  const DashboardHybridModeSetRequested(this.enabled);

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}

final class DashboardOverdriveModeSetRequested extends DashboardEvent {
  const DashboardOverdriveModeSetRequested(this.enabled);

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}

final class DashboardBatteryConservationSetRequested extends DashboardEvent {
  const DashboardBatteryConservationSetRequested(this.enabled);

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}

final class DashboardRapidChargingSetRequested extends DashboardEvent {
  const DashboardRapidChargingSetRequested(this.enabled);

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}

final class DashboardApplyContextFanPresetRequested extends DashboardEvent {
  const DashboardApplyContextFanPresetRequested();
}
