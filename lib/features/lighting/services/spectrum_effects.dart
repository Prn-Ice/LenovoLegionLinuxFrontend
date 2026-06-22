import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// A software lighting animation that we drive ourselves over the real-time
/// native path — so effects can run per-region (unlike the global-only hardware
/// effects) and without OpenRGB.
enum SpectrumEffect { pulse, wave, rainbow }

/// An [effect] bound to a set of LED indices, tinted from [color] and animated
/// at [speed] (cycles per second).
class SpectrumRegionEffect {
  const SpectrumRegionEffect({
    required this.ledIndices,
    required this.effect,
    required this.color,
    this.speed = 0.6,
  });

  final List<int> ledIndices;
  final SpectrumEffect effect;
  final Color color;
  final double speed;
}

double _wrapHue(double hue) => ((hue % 360) + 360) % 360;

/// The color for the [i]-th of [n] LEDs of [effect] at phase-time [tau]
/// (seconds × speed). Pure.
Color effectColorAt(
  SpectrumEffect effect,
  Color color,
  double tau,
  int i,
  int n,
) {
  switch (effect) {
    case SpectrumEffect.pulse:
      // Breathe the base color between off and full.
      final level = (math.sin(2 * math.pi * tau) + 1) / 2;
      return Color.fromARGB(
        255,
        (color.r * 255 * level).round(),
        (color.g * 255 * level).round(),
        (color.b * 255 * level).round(),
      );
    case SpectrumEffect.wave:
      // Sweep the base hue across the region over time.
      final spread = n <= 1 ? 0.0 : i / n;
      final hue = _wrapHue(
        HSVColor.fromColor(color).hue + (spread - tau) * 360,
      );
      return HSVColor.fromAHSV(1, hue, 1, 1).toColor();
    case SpectrumEffect.rainbow:
      // A full spectrum scrolling across the region.
      final spread = n <= 1 ? 0.0 : i / n;
      final hue = _wrapHue((spread - tau) * 360);
      return HSVColor.fromAHSV(1, hue, 1, 1).toColor();
  }
}

/// Composes an animated frame: starts from [base] and overlays each of
/// [effects] on its LEDs at time [t] (seconds). Pure — same inputs, same frame.
List<Color> composeEffectFrame({
  required List<Color> base,
  required List<SpectrumRegionEffect> effects,
  required double t,
}) {
  final out = List<Color>.of(base);
  for (final region in effects) {
    final n = region.ledIndices.length;
    for (var i = 0; i < n; i++) {
      final index = region.ledIndices[i];
      if (index < 0 || index >= out.length) continue;
      out[index] = effectColorAt(
        region.effect,
        region.color,
        t * region.speed,
        i,
        n,
      );
    }
  }
  return out;
}
