import 'dart:ui' show Color;

import 'package:equatable/equatable.dart';

import '../models/openrgb_device.dart';

/// Per-key RGB lighting state, driven by OpenRGB. Separate from the coarse
/// sysfs backlight [LightingState]; the page composes both.
class RgbLightingState extends Equatable {
  const RgbLightingState({
    this.available = false,
    this.device,
    this.activeMode,
    this.brightness = 100,
    this.selectedColor = const Color(0xFFD6409F),
    this.keyColors = const [],
    this.isLoading = false,
    this.isApplying = false,
    this.errorMessage,
    this.nativeAvailable = false,
    this.directColors = const [],
  });

  static const _unset = Object();

  /// Whether OpenRGB is reachable and exposes a controllable device.
  final bool available;

  /// The keyboard device, or null when unavailable.
  final OpenRgbDevice? device;

  /// The currently applied effect/mode (e.g. `Static`, `Direct`).
  final String? activeMode;

  /// Brightness 0–100 (write-only via the CLI; defaults to full).
  final int brightness;

  /// The color used to paint keys / tint color-modes.
  final Color selectedColor;

  /// Per-LED colors, indexed like [OpenRgbDevice.leds] (the Direct buffer).
  final List<Color> keyColors;

  final bool isLoading;
  final bool isApplying;
  final String? errorMessage;

  /// Whether the native (real-time, hidraw) Spectrum path is available — when
  /// true, per-key writes go direct instead of via the OpenRGB CLI.
  final bool nativeAvailable;

  /// The per-key Direct buffer saved when switching to a non-Direct mode, so
  /// returning to Direct restores the painting instead of a flat fill.
  final List<Color> directColors;

  RgbLightingState copyWith({
    bool? available,
    Object? device = _unset,
    Object? activeMode = _unset,
    int? brightness,
    Color? selectedColor,
    List<Color>? keyColors,
    bool? isLoading,
    bool? isApplying,
    Object? errorMessage = _unset,
    bool? nativeAvailable,
    List<Color>? directColors,
  }) {
    return RgbLightingState(
      available: available ?? this.available,
      device: device == _unset ? this.device : device as OpenRgbDevice?,
      activeMode: activeMode == _unset
          ? this.activeMode
          : activeMode as String?,
      brightness: brightness ?? this.brightness,
      selectedColor: selectedColor ?? this.selectedColor,
      keyColors: keyColors ?? this.keyColors,
      isLoading: isLoading ?? this.isLoading,
      isApplying: isApplying ?? this.isApplying,
      errorMessage: errorMessage == _unset
          ? this.errorMessage
          : errorMessage as String?,
      nativeAvailable: nativeAvailable ?? this.nativeAvailable,
      directColors: directColors ?? this.directColors,
    );
  }

  @override
  List<Object?> get props => [
    available,
    device,
    activeMode,
    brightness,
    selectedColor,
    keyColors,
    isLoading,
    isApplying,
    errorMessage,
    nativeAvailable,
    directColors,
  ];
}
