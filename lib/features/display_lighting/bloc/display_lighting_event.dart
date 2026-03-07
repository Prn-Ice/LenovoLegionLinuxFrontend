import 'package:equatable/equatable.dart';

sealed class DisplayLightingEvent extends Equatable {
  const DisplayLightingEvent();

  @override
  List<Object?> get props => const [];
}

final class DisplayLightingStarted extends DisplayLightingEvent {
  const DisplayLightingStarted();
}

final class DisplayLightingRefreshRequested extends DisplayLightingEvent {
  const DisplayLightingRefreshRequested();
}

final class HybridModeSetRequested extends DisplayLightingEvent {
  const HybridModeSetRequested(this.enabled);

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}

final class OverdriveModeSetRequested extends DisplayLightingEvent {
  const OverdriveModeSetRequested(this.enabled);

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}

final class WhiteKeyboardBacklightSetRequested extends DisplayLightingEvent {
  const WhiteKeyboardBacklightSetRequested(this.enabled);

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}

final class YLogoLightSetRequested extends DisplayLightingEvent {
  const YLogoLightSetRequested(this.enabled);

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}

final class IoPortLightSetRequested extends DisplayLightingEvent {
  const IoPortLightSetRequested(this.enabled);

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}

final class RefreshRateSetRequested extends DisplayLightingEvent {
  const RefreshRateSetRequested(this.rate);

  final double rate;

  @override
  List<Object?> get props => [rate];
}
