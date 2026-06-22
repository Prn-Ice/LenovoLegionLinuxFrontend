import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/lighting/models/openrgb_device.dart';

// A trimmed but representative `openrgb --list-devices` capture (real device,
// LED list shortened). The active mode is the one in [brackets]; multi-word
// names are 'quoted'.
const _fixture = '''
0: Lenovo Legion 7S Gen 8
  Type:           Keyboard
  Description:    Lenovo Legion 7 Slim Generation 8
  Modes: 'Screw Rainbow' 'Rainbow Wave' Smooth Rain Ripple Static 'Type Lighting' [Direct]
  Zones: Keyboard Neon
  LEDs: 'Key: Escape' 'Key: F1' 'Neon group 1'
''';

void main() {
  group('parseOpenRgbDevices', () {
    test('returns no devices for empty / server-noise-only output', () {
      expect(parseOpenRgbDevices(''), isEmpty);
      expect(parseOpenRgbDevices('Connected to server\n'), isEmpty);
    });

    test('parses the device header, type and description', () {
      final device = parseOpenRgbDevices(_fixture).single;
      expect(device.index, 0);
      expect(device.name, 'Lenovo Legion 7S Gen 8');
      expect(device.type, 'Keyboard');
      expect(device.description, 'Lenovo Legion 7 Slim Generation 8');
    });

    test('parses modes, keeping quoted multi-word names intact', () {
      final device = parseOpenRgbDevices(_fixture).single;
      expect(device.modes, [
        'Screw Rainbow',
        'Rainbow Wave',
        'Smooth',
        'Rain',
        'Ripple',
        'Static',
        'Type Lighting',
        'Direct',
      ]);
    });

    test('detects the active mode from the [bracketed] token', () {
      expect(parseOpenRgbDevices(_fixture).single.activeMode, 'Direct');
    });

    test('parses zones and LED names', () {
      final device = parseOpenRgbDevices(_fixture).single;
      expect(device.zones, ['Keyboard', 'Neon']);
      expect(device.leds, ['Key: Escape', 'Key: F1', 'Neon group 1']);
    });

    test('parses an LED name containing an apostrophe + the next LED', () {
      // OpenRGB quotes names without escaping, so the apostrophe key "Key: '"
      // is printed as 'Key: '' — the inner apostrophe must not be mistaken for
      // the closing quote (which would also mangle the following key).
      final device = parseOpenRgbDevices(
        "0: Pad\n  Type: Keyboard\n  LEDs: 'Key: ;' 'Key: '' 'Key: Enter'\n",
      ).single;
      expect(device.leds, ['Key: ;', "Key: '", 'Key: Enter']);
    });

    test('parses multiple device blocks', () {
      final devices = parseOpenRgbDevices(
        '$_fixture\n1: Some Other Device\n  Type:           DRAM\n',
      );
      expect(devices.map((d) => d.index), [0, 1]);
      expect(devices[1].name, 'Some Other Device');
      expect(devices[1].type, 'DRAM');
    });
  });
}
