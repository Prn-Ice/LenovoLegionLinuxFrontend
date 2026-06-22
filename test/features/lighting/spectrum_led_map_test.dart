import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/lighting/services/spectrum_led_map.dart';

void main() {
  group('kSpectrumLedValues', () {
    test('covers the 101 keys + 10 neon groups', () {
      expect(kSpectrumLedValues.length, 111);
      expect(kSpectrumLedValues['Key: Escape'], 0x01);
      expect(kSpectrumLedValues['Key: F12'], 0x0D);
      expect(kSpectrumLedValues['Neon group 1'], 0xF5);
      expect(kSpectrumLedValues['Neon group 10'], 0xFE);
    });

    test('has no duplicate hardware values', () {
      final values = kSpectrumLedValues.values.toList();
      expect(values.toSet().length, values.length);
    });
  });
}
