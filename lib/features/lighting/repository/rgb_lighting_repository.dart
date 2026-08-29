import 'dart:ui' show Color;

import '../models/rgb_lighting_device.dart';
import '../services/openrgb_cli_service.dart';

/// Formats a [Color] as OpenRGB's `RRGGBB` (uppercase, no leading `#`).
String colorToOpenRgbHex(Color color) {
  String channel(double v) => (v * 255.0)
      .round()
      .clamp(0, 255)
      .toRadixString(16)
      .padLeft(2, '0')
      .toUpperCase();
  return '${channel(color.r)}${channel(color.g)}${channel(color.b)}';
}

/// High-level keyboard RGB control over the OpenRGB CLI ([OpenRgbCliService]).
/// Maps app [Color]s to the CLI's hex/flag vocabulary.
class RgbLightingRepository {
  const RgbLightingRepository({
    OpenRgbCliService service = const OpenRgbCliService(),
  }) : _service = service;

  final OpenRgbCliService _service;

  /// The keyboard device (first `Keyboard`-type, else the first device), or
  /// null when OpenRGB exposes no devices / isn't running.
  Future<RgbLightingDevice?> loadKeyboard() async {
    final devices = await _service.listDevices();
    if (devices.isEmpty) return null;
    for (final device in devices) {
      if (device.type.toLowerCase() == 'keyboard') return device;
    }
    return devices.first;
  }

  /// Applies a named [mode] (effect), optionally with a single [color] and
  /// [brightness] (0–100).
  Future<void> applyMode(
    RgbLightingDevice device,
    String mode, {
    Color? color,
    int? brightness,
  }) {
    return _service.apply(
      device: device.index,
      mode: mode,
      colorsHex: color == null ? null : [colorToOpenRgbHex(color)],
      brightness: brightness,
    );
  }

  /// Paints each LED in order via Direct mode (per-key colors).
  Future<void> applyDirect(
    RgbLightingDevice device,
    List<Color> colors, {
    int? brightness,
  }) {
    return _service.apply(
      device: device.index,
      mode: 'Direct',
      colorsHex: colors.map(colorToOpenRgbHex).toList(),
      brightness: brightness,
    );
  }

  /// Sets brightness (0–100) without changing the mode.
  Future<void> setBrightness(RgbLightingDevice device, int percent) {
    return _service.apply(device: device.index, brightness: percent);
  }
}
