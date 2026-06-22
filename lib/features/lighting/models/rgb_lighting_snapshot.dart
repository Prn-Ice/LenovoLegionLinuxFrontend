import 'package:flutter/painting.dart';

import '../services/spectrum_effects.dart';

int _encodeColor(Color c) =>
    (255 << 24) |
    ((c.r * 255).round() << 16) |
    ((c.g * 255).round() << 8) |
    (c.b * 255).round();

Color _decodeColor(int v) => Color(v);

/// A persistable snapshot of the per-key RGB state: the Direct buffer, the
/// selected color, brightness, the active mode, and any software effects. The
/// keyboard can't report its per-key colors, so we remember them ourselves and
/// re-apply on launch. Round-trips through a primitive [Map] for Hive.
class RgbLightingSnapshot {
  const RgbLightingSnapshot({
    required this.keyColors,
    required this.selectedColor,
    required this.brightness,
    required this.activeMode,
    required this.effects,
  });

  final List<Color> keyColors;
  final Color selectedColor;
  final int brightness;
  final String? activeMode;
  final List<SpectrumRegionEffect> effects;

  Map<String, dynamic> toMap() => {
    'keyColors': [for (final c in keyColors) _encodeColor(c)],
    'selectedColor': _encodeColor(selectedColor),
    'brightness': brightness,
    'activeMode': activeMode,
    'effects': [
      for (final e in effects)
        {
          'scope': e.label,
          'leds': e.ledIndices,
          'effect': e.effect.index,
          'color': _encodeColor(e.color),
          'speed': e.speed,
        },
    ],
  };

  static RgbLightingSnapshot? fromMap(Map<String, dynamic> map) {
    final rawColors = map['keyColors'];
    if (rawColors is! List) return null;
    final effectsRaw = map['effects'];
    return RgbLightingSnapshot(
      keyColors: [for (final v in rawColors) _decodeColor(v as int)],
      selectedColor: _decodeColor((map['selectedColor'] as int?) ?? 0xFFD6409F),
      brightness: (map['brightness'] as int?) ?? 100,
      activeMode: map['activeMode'] as String?,
      effects: [
        if (effectsRaw is List)
          for (final raw in effectsRaw.whereType<Map>())
            SpectrumRegionEffect(
              label: (raw['scope'] as String?) ?? '',
              ledIndices: [for (final i in raw['leds'] as List) i as int],
              effect:
                  SpectrumEffect.values[(raw['effect'] as int).clamp(
                    0,
                    SpectrumEffect.values.length - 1,
                  )],
              color: _decodeColor((raw['color'] as int?) ?? 0xFFFFFFFF),
              speed: (raw['speed'] as num?)?.toDouble() ?? 0.6,
            ),
      ],
    );
  }
}
