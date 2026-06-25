import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/lighting/services/spectrum_protocol.dart';

void main() {
  group('capPowerRgb', () {
    test('passes colors under the per-LED power budget through unchanged', () {
      expect(capPowerRgb(255, 0, 0), (255, 0, 0)); // red
      expect(capPowerRgb(255, 0, 255), (255, 0, 255)); // magenta
      expect(capPowerRgb(160, 160, 160), (160, 160, 160)); // grey
      expect(capPowerRgb(0, 0, 0), (0, 0, 0));
    });

    test('scales near-white down to a displayable white, preserving hue', () {
      final (r, g, b) = capPowerRgb(255, 255, 255);
      expect(r + g + b, lessThanOrEqualTo(kSpectrumMaxLedSum));
      expect(r, g);
      expect(g, b); // stays neutral
      expect(r, greaterThan(220)); // still a bright white
    });
  });

  group('whiteBalanceRgb', () {
    test('pulls green down (the panel green is brighter), leaves red/blue', () {
      final (r, g, b) = whiteBalanceRgb(255, 255, 255);
      expect([r, b], [255, 255]); // red/blue untouched
      expect(g, lessThan(255)); // green reduced so equal RGB reads neutral
      expect(g, greaterThan(200)); // ~0.88x, not drastic
    });

    test('leaves a green-free color unchanged', () {
      expect(whiteBalanceRgb(255, 0, 128), (255, 0, 128));
    });
  });

  test('all packets are 960 bytes', () {
    expect(spectrumDirectModePacket(enable: true).length, kSpectrumPacketSize);
    expect(spectrumBrightnessPacket(6).length, kSpectrumPacketSize);
    expect(spectrumDirectFramePacket(const []).length, kSpectrumPacketSize);
  });

  group('spectrumDirectModePacket', () {
    test('enable / disable header with profile', () {
      expect(spectrumDirectModePacket(enable: true, profile: 2).sublist(0, 6), [
        0x07,
        0xD0,
        0xC0,
        0x03,
        0x01,
        2,
      ]);
      expect(
        spectrumDirectModePacket(enable: false, profile: 2).sublist(0, 6),
        [0x07, 0xD0, 0xC0, 0x03, 0x02, 2],
      );
    });
  });

  test('spectrumBrightnessPacket', () {
    expect(spectrumBrightnessPacket(6).sublist(0, 5), [
      0x07,
      0xCE,
      0xC0,
      0x03,
      6,
    ]);
  });

  group('spectrumDirectFramePacket', () {
    test('writes the header then LED blocks (value LE + RGB)', () {
      final packet = spectrumDirectFramePacket([
        const SpectrumLed(0x1234, 0xAA, 0xBB, 0xCC),
        const SpectrumLed(0x0056, 1, 2, 3),
      ]);
      expect(packet.sublist(0, 4), [0x07, 0xA1, 0xC0, 0x03]);
      expect(packet.sublist(4, 9), [0x34, 0x12, 0xAA, 0xBB, 0xCC]);
      expect(packet.sublist(9, 14), [0x56, 0x00, 1, 2, 3]);
    });

    test('fits all 113 keys in a single packet', () {
      final leds = [for (var i = 1; i <= 113; i++) SpectrumLed(i, 0, 0, 0)];
      final packet = spectrumDirectFramePacket(leds);
      expect(packet.length, kSpectrumPacketSize);
      // 4-byte header + 113*5 = 569 bytes; the 113th block's value-lo == 113.
      expect(packet[4 + 112 * 5], 113);
    });
  });

  group('hidioc ioctl numbers', () {
    test('set / get feature for a 960-byte report', () {
      expect(hidiocSetFeature(960), 0xC3C04806);
      expect(hidiocGetFeature(960), 0xC3C04807);
    });
  });
}
