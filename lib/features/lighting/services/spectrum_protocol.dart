import 'dart:typed_data';

/// Wire format for the Lenovo Legion "Spectrum" per-key keyboard, **Gen 7/8**
/// (ITE 8258, e.g. 048d:c987). Ported from OpenRGB's `LenovoUSBController_Gen7_8`.
/// Pure byte-packing so it's unit-tested without touching the device.
///
/// Every feature report is 960 bytes, report id `0x07`, with a `0xC0, 0x03`
/// preamble after the opcode. Per-key direct flow: enable direct mode (`0xD0`),
/// then push a frame (`0xA1`) of `[ledValue(LE16), R, G, B]` blocks — all ~113
/// keys fit in one packet. LED values start at 1 (`0` terminates the frame).

const int kSpectrumPacketSize = 960;

/// Max per-LED total (R+G+B) the keyboard will actually light. Above this the
/// firmware drops the LED (a per-key power cap), so full white (765) shows as
/// nothing — measured on hardware: 720 lights, 762 doesn't.
const int kSpectrumMaxLedSum = 720;

/// Caps an LED's [r],[g],[b] to the per-key power budget, scaling all channels
/// proportionally (so hue is preserved) only when the total exceeds the budget.
/// Colors under it pass through unchanged.
(int, int, int) capPowerRgb(int r, int g, int b) {
  final sum = r + g + b;
  if (sum <= kSpectrumMaxLedSum || sum == 0) return (r, g, b);
  final scale = kSpectrumMaxLedSum / sum;
  return ((r * scale).round(), (g * scale).round(), (b * scale).round());
}

const int _reportId = 0x07;
const int _directMode = 0xA1; // push a direct frame
const int _setDirectMode = 0xD0; // enable/disable direct mode
const int _setBrightness = 0xCE;
const int _getActiveProfile = 0xCA;

/// One LED's hardware [number] (uint16) and RGB for a direct frame.
class SpectrumLed {
  const SpectrumLed(this.number, this.r, this.g, this.b);

  final int number;
  final int r;
  final int g;
  final int b;
}

Uint8List _packet(List<int> head) {
  final buffer = Uint8List(kSpectrumPacketSize);
  buffer.setRange(0, head.length, head);
  return buffer;
}

/// Enables (or disables) direct mode for [profile] — required before pushing
/// direct frames so the keyboard listens to per-key colors.
Uint8List spectrumDirectModePacket({required bool enable, int profile = 1}) =>
    _packet([
      _reportId,
      _setDirectMode,
      0xC0,
      0x03,
      enable ? 0x01 : 0x02,
      profile,
    ]);

/// Sets keyboard brightness (0–255; the device exposes 0–9 in practice).
Uint8List spectrumBrightnessPacket(int brightness) =>
    _packet([_reportId, _setBrightness, 0xC0, 0x03, brightness & 0xFF]);

/// Reads the active profile id — send via HIDIOCGFEATURE; profile is byte 4 of
/// the response.
Uint8List spectrumGetActiveProfilePacket() =>
    _packet([_reportId, _getActiveProfile, 0xC0, 0x03]);

/// Builds the direct frame for [leds]: `[0x07, 0xA1, 0xC0, 0x03,
/// (valueLo, valueHi, R, G, B)…]`, the rest zero-padded (a zero value ends it).
Uint8List spectrumDirectFramePacket(List<SpectrumLed> leds) {
  final buffer = Uint8List(kSpectrumPacketSize);
  buffer[0] = _reportId;
  buffer[1] = _directMode;
  buffer[2] = 0xC0;
  buffer[3] = 0x03;
  var offset = 4;
  for (final led in leds) {
    if (offset + 5 > kSpectrumPacketSize) break;
    buffer[offset++] = led.number & 0xFF;
    buffer[offset++] = (led.number >> 8) & 0xFF;
    buffer[offset++] = led.r & 0xFF;
    buffer[offset++] = led.g & 0xFF;
    buffer[offset++] = led.b & 0xFF;
  }
  return buffer;
}

/// The Linux `HIDIOCSFEATURE(length)` ioctl request — send a feature report:
/// `_IOC(_IOC_READ|_IOC_WRITE, 'H', 0x06, length)`.
int hidiocSetFeature(int length) =>
    (3 << 30) | (0x48 << 8) | 0x06 | (length << 16);

/// The Linux `HIDIOCGFEATURE(length)` ioctl request — get a feature report:
/// `_IOC(_IOC_READ|_IOC_WRITE, 'H', 0x07, length)`.
int hidiocGetFeature(int length) =>
    (3 << 30) | (0x48 << 8) | 0x07 | (length << 16);
