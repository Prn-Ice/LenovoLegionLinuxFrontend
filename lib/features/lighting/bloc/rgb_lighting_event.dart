import 'dart:ui' show Color;

import 'package:equatable/equatable.dart';

import '../services/spectrum_effects.dart';

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

/// Turn a single LED off (Direct mode) — shift-click "erase".
final class RgbKeyErased extends RgbLightingEvent {
  const RgbKeyErased(this.ledIndex);

  final int ledIndex;

  @override
  List<Object?> get props => [ledIndex];
}

/// Copy an LED's current color into the selected color (eyedropper).
final class RgbKeyPicked extends RgbLightingEvent {
  const RgbKeyPicked(this.ledIndex);

  final int ledIndex;

  @override
  List<Object?> get props => [ledIndex];
}

/// Paint a subset of LEDs (by index) with the selected color — region fills.
final class RgbRegionFilled extends RgbLightingEvent {
  const RgbRegionFilled(this.ledIndices);

  final List<int> ledIndices;

  @override
  List<Object?> get props => [ledIndices];
}

/// Assign a software animated [effect] to the [ledIndices] of a named [scope]
/// (replacing any effect already on that scope), tinted by the selected color.
final class RgbEffectAssigned extends RgbLightingEvent {
  const RgbEffectAssigned(this.scope, this.ledIndices, this.effect);

  final String scope;
  final List<int> ledIndices;
  final SpectrumEffect effect;

  @override
  List<Object?> get props => [scope, ledIndices, effect];
}

/// Stop and remove all software animated effects.
final class RgbEffectsCleared extends RgbLightingEvent {
  const RgbEffectsCleared();
}

/// Save the current setup as a named profile.
final class RgbProfileSaved extends RgbLightingEvent {
  const RgbProfileSaved(this.name);

  final String name;

  @override
  List<Object?> get props => [name];
}

/// Load a named profile and apply it to the keyboard.
final class RgbProfileLoaded extends RgbLightingEvent {
  const RgbProfileLoaded(this.name);

  final String name;

  @override
  List<Object?> get props => [name];
}

/// Delete a named profile.
final class RgbProfileDeleted extends RgbLightingEvent {
  const RgbProfileDeleted(this.name);

  final String name;

  @override
  List<Object?> get props => [name];
}

/// Fill every LED with [color] (Direct mode) — the basis for presets.
final class RgbAllKeysFilled extends RgbLightingEvent {
  const RgbAllKeysFilled(this.color);

  final Color color;

  @override
  List<Object?> get props => [color];
}
