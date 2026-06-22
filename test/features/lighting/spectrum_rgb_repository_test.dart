import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/lighting/repository/spectrum_rgb_repository.dart';
import 'package:legion_frontend/features/lighting/services/spectrum_hid_service.dart';
import 'package:legion_frontend/features/lighting/services/spectrum_protocol.dart';

class _FakeService extends SpectrumHidService {
  String? path = '/dev/hidraw0';
  List<SpectrumLed>? lastFrame;
  int? lastBrightness;

  @override
  String? findHidrawPath() => path;

  @override
  bool sendDirectFrame(List<SpectrumLed> leds) {
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

    test('caps full white to the per-LED power budget so it lights', () {
      final led = spectrumLedsFor(
        const ['Key: Escape'],
        const [Color(0xFFFFFFFF)],
      ).single;
      expect(led.r + led.g + led.b, lessThanOrEqualTo(720));
      expect([led.r, led.g, led.b], everyElement(greaterThan(220)));
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
      expect(fake.lastFrame!.single.g, 255);
    });

    test('setBrightness maps the percentage to a device level', () {
      final fake = _FakeService();
      SpectrumRgbRepository(service: fake).setBrightness(100);
      expect(fake.lastBrightness, 9);
    });
  });
}
