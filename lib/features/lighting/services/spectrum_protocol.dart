import 'dart:typed_data';

/// Wire format for the Lenovo Legion "Spectrum" per-key keyboard (ITE 8258,
/// Gen 7/8 protocol, e.g. 048d:c987). Ported from OpenRGB's LenovoUSBController.
/// Pure byte-packing so it's unit-tested without touching the device.

/// Every feature report is exactly this many bytes.
const int kSpectrumPacketSize = 192;

const int _instructionStart = 0x07;
const int _zoneId0 = 0xA0;
const int _maxLedsPerPacket = 0x2F; // 47
const int _softwareMode = 0xB2;
const int _hardwareMode = 0xB1;

/// One LED's hardware [number] and RGB for a direct frame.
class SpectrumLed {
  const SpectrumLed(this.number, this.r, this.g, this.b);

  final int number;
  final int r;
  final int g;
  final int b;
}

/// "Software mode" report — must be sent before direct writes so the keyboard
/// listens to the software protocol instead of its onboard controller.
Uint8List spectrumSoftwareModePacket() => _instruction(_softwareMode);

/// Releases the device back to onboard (hardware) control.
Uint8List spectrumHardwareModePacket() => _instruction(_hardwareMode);

Uint8List _instruction(int instruction) {
  final buffer = Uint8List(kSpectrumPacketSize);
  buffer[0] = _instructionStart;
  buffer[1] = instruction;
  return buffer;
}

/// The Linux `HIDIOCSFEATURE(length)` ioctl request number — send a feature
/// report of [length] bytes: `_IOC(_IOC_READ|_IOC_WRITE, 'H', 0x06, length)`.
int hidiocSetFeature(int length) =>
    (3 << 30) | (0x48 << 8) | 0x06 | (length << 16);

/// Builds the direct-mode feature reports for [leds] on [zone] (0 = keyboard),
/// split into packets of at most 47 LEDs. Each LED block is
/// `[number, R, G, B]` at offset `i*4 + 4`.
List<Uint8List> spectrumDirectPackets(List<SpectrumLed> leds, {int zone = 0}) {
  final packets = <Uint8List>[];
  for (var start = 0; start < leds.length; start += _maxLedsPerPacket) {
    final end = start + _maxLedsPerPacket < leds.length
        ? start + _maxLedsPerPacket
        : leds.length;
    final buffer = Uint8List(kSpectrumPacketSize);
    buffer[0] = _instructionStart;
    buffer[1] = _zoneId0 + zone;
    buffer[2] = end - start;
    buffer[3] = 0;
    for (var i = start; i < end; i++) {
      final offset = (i - start) * 4 + 4;
      buffer[offset] = leds[i].number & 0xFF;
      buffer[offset + 1] = leds[i].r & 0xFF;
      buffer[offset + 2] = leds[i].g & 0xFF;
      buffer[offset + 3] = leds[i].b & 0xFF;
    }
    packets.add(buffer);
  }
  return packets;
}
