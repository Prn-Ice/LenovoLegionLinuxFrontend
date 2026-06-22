import 'dart:ui' show Color;

import '../services/spectrum_hid_service.dart';
import '../services/spectrum_led_map.dart';
import '../services/spectrum_protocol.dart';

/// Maps a 0–100 brightness percentage to the device's 0–9 range.
int spectrumBrightnessLevel(int percent) =>
    (percent.clamp(0, 100) * 9 / 100).round();

/// Builds native [SpectrumLed]s from per-LED [colors] aligned positionally to
/// [ledNames] (our `OpenRgbDevice.leds` order). Names with no hardware value
/// are skipped.
List<SpectrumLed> spectrumLedsFor(List<String> ledNames, List<Color> colors) {
  final result = <SpectrumLed>[];
  final count = ledNames.length < colors.length
      ? ledNames.length
      : colors.length;
  for (var i = 0; i < count; i++) {
    final value = kSpectrumLedValues[ledNames[i]];
    if (value == null) continue;
    final color = colors[i];
    result.add(
      SpectrumLed(
        value,
        (color.r * 255.0).round(),
        (color.g * 255.0).round(),
        (color.b * 255.0).round(),
      ),
    );
  }
  return result;
}

/// Real-time per-key keyboard RGB over the native Spectrum HID path — drives the
/// keyboard directly (no OpenRGB). The caller is responsible for OpenRGB being
/// out of the way (the two can't both own the device).
class SpectrumRgbRepository {
  SpectrumRgbRepository({SpectrumHidService? service})
    : _service = service ?? SpectrumHidService();

  final SpectrumHidService _service;

  /// True when the Spectrum keyboard's hidraw node is present.
  bool get isAvailable => _service.findHidrawPath() != null;

  /// Paints the keyboard from per-LED [colors] aligned to [ledNames]. Returns
  /// false if nothing mapped or the write failed.
  bool paint(List<String> ledNames, List<Color> colors) {
    final leds = spectrumLedsFor(ledNames, colors);
    if (leds.isEmpty) return false;
    return _service.sendDirectFrame(leds);
  }

  /// Sets brightness as a 0–100 percentage.
  bool setBrightness(int percent) =>
      _service.setBrightness(spectrumBrightnessLevel(percent));

  void dispose() => _service.close();
}
