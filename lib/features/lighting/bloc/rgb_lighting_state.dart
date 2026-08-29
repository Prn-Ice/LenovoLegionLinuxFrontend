import 'dart:ui' show Color;

import 'package:equatable/equatable.dart';

import '../models/rgb_lighting_device.dart';
import '../services/spectrum_effects.dart';

/// Per-key RGB lighting state, driven by native Spectrum HID when available and
/// otherwise by OpenRGB. Separate from the coarse sysfs backlight state.
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
    this.nativeAvailabilityError,
    this.directColors = const [],
    this.effects = const [],
    this.profileNames = const [],
  });

  static const _unset = Object();

  /// Whether either backend exposes a controllable RGB device.
  final bool available;

  /// The keyboard device, or null when unavailable.
  final RgbLightingDevice? device;

  /// The currently applied effect/mode (e.g. `Static`, `Direct`).
  final String? activeMode;

  /// Brightness 0–100; defaults to full.
  final int brightness;

  /// The color used to paint keys / tint color-modes.
  final Color selectedColor;

  /// Per-LED colors, indexed like [RgbLightingDevice.leds] (the Direct buffer).
  final List<Color> keyColors;

  final bool isLoading;
  final bool isApplying;
  final String? errorMessage;

  /// Whether the native (real-time, hidraw) Spectrum path is available — when
  /// true, per-key writes go direct instead of via the OpenRGB CLI.
  final bool nativeAvailable;

  /// A probe failure is distinct from a missing native device. This lets the
  /// UI avoid suggesting OpenRGB when the native backend needs attention.
  final String? nativeAvailabilityError;

  /// The per-key Direct buffer saved when switching to a non-Direct mode, so
  /// returning to Direct restores the painting instead of a flat fill.
  final List<Color> directColors;

  /// Active software animated effects, each bound to a region of LEDs.
  final List<SpectrumRegionEffect> effects;

  /// Names of saved named profiles, in creation order.
  final List<String> profileNames;

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
    Object? nativeAvailabilityError = _unset,
    List<Color>? directColors,
    List<SpectrumRegionEffect>? effects,
    List<String>? profileNames,
  }) {
    return RgbLightingState(
      available: available ?? this.available,
      device: device == _unset ? this.device : device as RgbLightingDevice?,
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
      nativeAvailabilityError: nativeAvailabilityError == _unset
          ? this.nativeAvailabilityError
          : nativeAvailabilityError as String?,
      directColors: directColors ?? this.directColors,
      effects: effects ?? this.effects,
      profileNames: profileNames ?? this.profileNames,
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
    nativeAvailabilityError,
    directColors,
    effects,
    profileNames,
  ];
}
