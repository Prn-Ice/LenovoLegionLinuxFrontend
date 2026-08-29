import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/lighting/repository/spectrum_rgb_repository.dart';
import 'package:legion_frontend/features/lighting/services/spectrum_hid_service.dart';
import 'package:legion_frontend/features/lighting/services/spectrum_protocol.dart';

class _FakeService extends SpectrumHidService {
  String? path = '/dev/hidraw0';
  List<SpectrumLed>? lastFrame;
  int? lastBrightness;
  int frameCount = 0;

  @override
  String? findHidrawPath() => path;

  @override
  bool sendDirectFrame(List<SpectrumLed> leds) {
    frameCount++;
    lastFrame = leds;
    return true;
  }

  @override
  bool setBrightness(int brightness) {
    lastBrightness = brightness;
    return true;
  }
}

void main() {
  group('spectrumBrightnessLevel', () {
    test('maps 0–100% onto 0–9', () {
      expect(spectrumBrightnessLevel(0), 0);
      expect(spectrumBrightnessLevel(100), 9);
      expect(spectrumBrightnessLevel(50), 5); // 4.5 -> 5
    });
  });

  group('spectrumGreenGainForBrightness', () {
    test('uses measured dim and full-brightness gains', () {
      expect(spectrumGreenGainForBrightness(33), closeTo(0.94, 0.001));
      expect(
        spectrumGreenGainForBrightness(100),
        closeTo(kSpectrumGreenGain, 0.001),
      );
    });

    test('interpolates between measured brightness levels', () {
      expect(spectrumGreenGainForBrightness(67), closeTo(0.91, 0.001));
    });
  });

  group('spectrumLedsFor', () {
    test('maps known names + RGB and skips unknown', () {
      final leds = spectrumLedsFor(
        const ['Key: Escape', 'Bogus'],
        const [Color(0xFFFF0000), Color(0xFFFFFFFF)],
      );
      expect(leds.length, 1);
      expect(leds.single.number, 0x01);
      expect([leds.single.r, leds.single.g, leds.single.b], [255, 0, 0]);
    });

    test('caps + white-balances full white so it lights neutral', () {
      final led = spectrumLedsFor(
        const ['Key: Escape'],
        const [Color(0xFFFFFFFF)],
      ).single;
      expect(led.r + led.g + led.b, lessThanOrEqualTo(720)); // lit (power cap)
      expect([led.r, led.g, led.b], everyElement(greaterThan(150))); // all on
      expect(led.g, lessThan(led.r)); // green pulled down (white balance)
    });
  });

  group('SpectrumRgbRepository', () {
    test('isAvailable reflects hidraw presence', () {
      final fake = _FakeService();
      final repo = SpectrumRgbRepository(service: fake);
      expect(repo.isAvailable, isTrue);
      fake.path = null;
      expect(repo.isAvailable, isFalse);
    });

    test('paint converts colors and sends a frame', () {
      final fake = _FakeService();
      final ok = SpectrumRgbRepository(
        service: fake,
      ).paint(const ['Key: Escape'], const [Color(0xFF00FF00)]);
      expect(ok, isTrue);
      expect(fake.lastFrame!.single.number, 0x01);
      expect(
        fake.lastFrame!.single.g,
        greaterThan(200),
      ); // white-balanced (~224)
    });

    test('setBrightness maps the percentage to a device level', () {
      final fake = _FakeService();
      SpectrumRgbRepository(service: fake).setBrightness(100);
      expect(fake.lastBrightness, 9);
    });

    test(
      'brightness changes repaint the last frame with the adjusted gain',
      () {
        final fake = _FakeService();
        final repo = SpectrumRgbRepository(service: fake);
        repo.paint(const ['Key: Escape'], const [Color(0xFFFFFFFF)]);
        final fullBrightnessGreen = fake.lastFrame!.single.g;

        expect(repo.setBrightness(33), isTrue);

        expect(fake.lastBrightness, 3);
        expect(fake.frameCount, 2);
        expect(fake.lastFrame!.single.g, greaterThan(fullBrightnessGreen));
      },
    );
  });
}
