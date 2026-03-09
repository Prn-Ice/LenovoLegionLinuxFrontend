import 'package:equatable/equatable.dart';

sealed class LightingEvent extends Equatable {
  const LightingEvent();

  @override
  List<Object?> get props => const [];
}

final class LightingStarted extends LightingEvent {
  const LightingStarted();
}

final class LightingTicked extends LightingEvent {
  const LightingTicked();
}

final class WhiteKeyboardBacklightSetRequested extends LightingEvent {
  const WhiteKeyboardBacklightSetRequested(this.enabled);

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}

final class YLogoLightSetRequested extends LightingEvent {
  const YLogoLightSetRequested(this.enabled);

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}

final class IoPortLightSetRequested extends LightingEvent {
  const IoPortLightSetRequested(this.enabled);

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}
