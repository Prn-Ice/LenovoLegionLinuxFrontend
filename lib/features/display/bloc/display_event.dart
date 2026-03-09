import 'package:equatable/equatable.dart';

sealed class DisplayEvent extends Equatable {
  const DisplayEvent();

  @override
  List<Object?> get props => const [];
}

final class DisplayStarted extends DisplayEvent {
  const DisplayStarted();
}

final class DisplayRefreshRequested extends DisplayEvent {
  const DisplayRefreshRequested();
}

final class DisplayTicked extends DisplayEvent {
  const DisplayTicked();
}

final class OverdriveModeSetRequested extends DisplayEvent {
  const OverdriveModeSetRequested(this.enabled);

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}

final class RefreshRateSetRequested extends DisplayEvent {
  const RefreshRateSetRequested(this.rate);

  final double rate;

  @override
  List<Object?> get props => [rate];
}
