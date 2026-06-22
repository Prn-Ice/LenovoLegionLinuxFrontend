import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/lighting/services/spectrum_effects.dart';

void main() {
  group('effectColorAt', () {
    test('pulse peaks at full color and bottoms out at off', () {
      const green = Color(0xFF00FF00);
      expect(effectColorAt(SpectrumEffect.pulse, green, 0.25, 0, 1), green);
      expect(
        effectColorAt(SpectrumEffect.pulse, green, 0.75, 0, 1),
        const Color(0xFF000000),
      );
    });

    test('rainbow starts red at the head of the region', () {
      expect(
        effectColorAt(SpectrumEffect.rainbow, const Color(0xFFFFFFFF), 0, 0, 1),
        const Color(0xFFFF0000),
      );
    });

    test('wave keeps the base hue at the head at t=0', () {
      final c = effectColorAt(
        SpectrumEffect.wave,
        const Color(0xFF0000FF),
        0,
        0,
        1,
      );
      expect(HSVColor.fromColor(c).hue, closeTo(240, 0.5)); // blue
    });
  });

  group('composeEffectFrame', () {
    test('overlays only the effect LEDs, leaving the base intact', () {
      final base = List<Color>.filled(3, const Color(0xFF111111));
      final frame = composeEffectFrame(
        base: base,
        effects: const [
          SpectrumRegionEffect(
            ledIndices: [1],
            effect: SpectrumEffect.pulse,
            color: Color(0xFF00FF00),
            speed: 1,
          ),
        ],
        t: 0.25, // pulse peak
      );
      expect(frame[0], const Color(0xFF111111));
      expect(frame[1], const Color(0xFF00FF00));
      expect(frame[2], const Color(0xFF111111));
    });

    test('ignores out-of-range indices', () {
      final frame = composeEffectFrame(
        base: List<Color>.filled(2, const Color(0xFF000000)),
        effects: const [
          SpectrumRegionEffect(
            ledIndices: [5],
            effect: SpectrumEffect.rainbow,
            color: Color(0xFFFFFFFF),
          ),
        ],
        t: 0.1,
      );
      expect(frame, everyElement(const Color(0xFF000000)));
    });
  });
}
