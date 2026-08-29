import 'dart:ui' show Color;

import '../services/spectrum_hid_service.dart';
import '../services/spectrum_led_map.dart';
import '../services/spectrum_protocol.dart';

/// Maps a 0–100 brightness percentage to the device's 0–9 range.
int spectrumBrightnessLevel(int percent) =>
    (percent.clamp(0, 100) * 9 / 100).round();

/// Dim output needs slightly more green than full brightness to remain neutral.
/// Hardware measurements found 0.94 neutral at levels 0-3 and 0.88 at level 9.
double spectrumGreenGainForBrightness(int percent) {
  final level = spectrumBrightnessLevel(percent);
  if (level <= 3) return 0.94;
  return 0.94 - ((level - 3) / 6) * (0.94 - kSpectrumGreenGain);
}

/// Builds native [SpectrumLed]s from per-LED [colors] aligned positionally to
/// [ledNames] (our `RgbLightingDevice.leds` order). Names with no hardware value
/// are skipped.
List<SpectrumLed> spectrumLedsFor(
  List<String> ledNames,
  List<Color> colors, {
  double greenGain = kSpectrumGreenGain,
}) {
  final result = <SpectrumLed>[];
  final count = ledNames.length < colors.length
      ? ledNames.length
      : colors.length;
  for (var i = 0; i < count; i++) {
    final value = kSpectrumLedValues[ledNames[i]];
    if (value == null) continue;
    final color = colors[i];
    final (wr, wg, wb) = whiteBalanceRgb(
      (color.r * 255.0).round(),
      (color.g * 255.0).round(),
      (color.b * 255.0).round(),
      greenGain: greenGain,
    );
    final (r, g, b) = capPowerRgb(wr, wg, wb);
    result.add(SpectrumLed(value, r, g, b));
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
  int _brightness = 100;
  List<String>? _lastLedNames;
  List<Color>? _lastColors;

  /// True when the Spectrum keyboard's hidraw node is present.
  bool get isAvailable => _service.findHidrawPath() != null;

  /// Paints the keyboard from per-LED [colors] aligned to [ledNames]. Returns
  /// false if nothing mapped or the write failed.
  bool paint(List<String> ledNames, List<Color> colors) {
    _lastLedNames = List.of(ledNames);
    _lastColors = List.of(colors);
    return _sendLastFrame();
  }

  bool _sendLastFrame() {
    final ledNames = _lastLedNames;
    final colors = _lastColors;
    if (ledNames == null || colors == null) return true;
    final leds = spectrumLedsFor(
      ledNames,
      colors,
      greenGain: spectrumGreenGainForBrightness(_brightness),
    );
    if (leds.isEmpty) return false;
    return _service.sendDirectFrame(leds);
  }

  /// Sets brightness as a 0–100 percentage.
  bool setBrightness(int percent) {
    final brightness = percent.clamp(0, 100);
    if (!_service.setBrightness(spectrumBrightnessLevel(brightness))) {
      return false;
    }
    _brightness = brightness;
    return _sendLastFrame();
  }

  void dispose() => _service.close();
}
