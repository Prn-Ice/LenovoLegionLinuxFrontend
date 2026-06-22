import 'dart:ui' show Color;

import 'package:equatable/equatable.dart';

sealed class RgbLightingEvent extends Equatable {
  const RgbLightingEvent();

  @override
  List<Object?> get props => const [];
}

/// Load the keyboard device and initialize the buffer.
final class RgbLightingStarted extends RgbLightingEvent {
  const RgbLightingStarted();
}

/// Reload the device (e.g. after OpenRGB starts).
final class RgbLightingRefreshRequested extends RgbLightingEvent {
  const RgbLightingRefreshRequested();
}

/// Apply a named effect/mode, tinted with the selected color.
final class RgbModeSelected extends RgbLightingEvent {
  const RgbModeSelected(this.mode);

  final String mode;

  @override
  List<Object?> get props => [mode];
}

/// Change the paint/effect color (does not apply on its own).
final class RgbColorSelected extends RgbLightingEvent {
  const RgbColorSelected(this.color);

  final Color color;

  @override
  List<Object?> get props => [color];
}

/// Set brightness (0–100).
final class RgbBrightnessChanged extends RgbLightingEvent {
  const RgbBrightnessChanged(this.brightness);

  final int brightness;

  @override
  List<Object?> get props => [brightness];
}

/// Paint a single LED with the selected color (Direct mode).
final class RgbKeyPainted extends RgbLightingEvent {
  const RgbKeyPainted(this.ledIndex);

  final int ledIndex;

  @override
  List<Object?> get props => [ledIndex];
}

/// Fill every LED with [color] (Direct mode) — the basis for presets.
final class RgbAllKeysFilled extends RgbLightingEvent {
  const RgbAllKeysFilled(this.color);

  final Color color;

  @override
  List<Object?> get props => [color];
}
