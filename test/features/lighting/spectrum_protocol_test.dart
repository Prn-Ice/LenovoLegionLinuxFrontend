import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/lighting/services/spectrum_protocol.dart';

void main() {
  group('spectrumSoftwareModePacket', () {
    test('is a 192-byte [0x07, 0xB2, 0, …] feature report', () {
      final packet = spectrumSoftwareModePacket();
      expect(packet.length, kSpectrumPacketSize);
      expect(packet[0], 0x07);
      expect(packet[1], 0xB2);
      expect(packet.skip(2).every((b) => b == 0), isTrue);
    });
  });

  group('spectrumDirectPackets', () {
    test('encodes a single LED: header + ledNum + RGB at offset 4', () {
      final packets = spectrumDirectPackets([
        const SpectrumLed(5, 0xFF, 0x80, 0x00),
      ]);
      expect(packets.length, 1);
      final packet = packets.single;
      expect(packet.length, kSpectrumPacketSize);
      expect(packet.sublist(0, 8), [0x07, 0xA0, 1, 0, 5, 0xFF, 0x80, 0x00]);
    });

    test('packs up to 47 LEDs in one packet', () {
      final leds = [for (var i = 0; i < 47; i++) SpectrumLed(i, i, 0, 0)];
      final packets = spectrumDirectPackets(leds);
      expect(packets.length, 1);
      expect(packets.single[2], 47);
    });

    test('splits 113 LEDs into 47 + 47 + 19', () {
      final leds = [for (var i = 0; i < 113; i++) SpectrumLed(i, 0, 0, 0)];
      final packets = spectrumDirectPackets(leds);
      expect(packets.map((p) => p[2]).toList(), [47, 47, 19]);
    });

    test('applies the zone offset to the header byte', () {
      final packets = spectrumDirectPackets([
        const SpectrumLed(0, 0, 0, 0),
      ], zone: 1);
      expect(packets.single[1], 0xA1);
    });

    test('writes each LED block at offset i*4+4', () {
      final packets = spectrumDirectPackets([
        const SpectrumLed(10, 1, 2, 3),
        const SpectrumLed(20, 4, 5, 6),
      ]);
      final packet = packets.single;
      expect(packet.sublist(4, 8), [10, 1, 2, 3]);
      expect(packet.sublist(8, 12), [20, 4, 5, 6]);
    });

    test('no LEDs yields no packets', () {
      expect(spectrumDirectPackets(const []), isEmpty);
    });
  });
}
