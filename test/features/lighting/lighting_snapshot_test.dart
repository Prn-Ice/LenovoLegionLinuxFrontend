import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/lighting/models/rgb_lighting_snapshot.dart';
import 'package:legion_frontend/features/lighting/services/spectrum_effects.dart';

void main() {
  test('round-trips colors, brightness, mode and effects through a map', () {
    const snapshot = RgbLightingSnapshot(
      keyColors: [Color(0xFFFF0000), Color(0xFF00FF00), Color(0xFF000000)],
      selectedColor: Color(0xFF0000FF),
      brightness: 70,
      activeMode: 'Direct',
      effects: [
        SpectrumRegionEffect(
          ledIndices: [3, 4],
          effect: SpectrumEffect.wave,
          color: Color(0xFF112233),
          speed: 0.8,
          label: 'Numpad',
        ),
      ],
    );

    final restored = RgbLightingSnapshot.fromMap(snapshot.toMap())!;

    expect(restored.keyColors, [
      const Color(0xFFFF0000),
      const Color(0xFF00FF00),
      const Color(0xFF000000),
    ]);
    expect(restored.selectedColor, const Color(0xFF0000FF));
    expect(restored.brightness, 70);
    expect(restored.activeMode, 'Direct');
    expect(restored.effects.single.label, 'Numpad');
    expect(restored.effects.single.ledIndices, [3, 4]);
    expect(restored.effects.single.effect, SpectrumEffect.wave);
    expect(restored.effects.single.color, const Color(0xFF112233));
    expect(restored.effects.single.speed, 0.8);
  });

  test('returns null when the payload has no key colors', () {
    expect(RgbLightingSnapshot.fromMap(const {}), isNull);
  });
}
