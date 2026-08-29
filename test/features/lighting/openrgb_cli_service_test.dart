import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/lighting/services/openrgb_cli_service.dart';

void main() {
  group('openRgbApplyArgs', () {
    test('mode only', () {
      expect(openRgbApplyArgs(device: 0, mode: 'Static'), [
        '-d',
        '0',
        '-m',
        'Static',
      ]);
    });

    test('mode + single color', () {
      expect(
        openRgbApplyArgs(device: 0, mode: 'Static', colorsHex: ['FF0000']),
        ['-d', '0', '-m', 'Static', '-c', 'FF0000'],
      );
    });

    test('per-key colors join with commas (Direct mode)', () {
      expect(
        openRgbApplyArgs(
          device: 0,
          mode: 'Direct',
          colorsHex: ['FF0000', '00FF00'],
        ),
        ['-d', '0', '-m', 'Direct', '-c', 'FF0000,00FF00'],
      );
    });

    test('zone, brightness and speed, in CLI-required order', () {
      expect(
        openRgbApplyArgs(
          device: 0,
          zone: 1,
          mode: 'Rainbow Wave',
          brightness: 80,
          speed: 50,
        ),
        ['-d', '0', '-z', '1', '-m', 'Rainbow Wave', '-b', '80', '-s', '50'],
      );
    });

    test('color without a mode sets LEDs directly', () {
      expect(openRgbApplyArgs(device: 0, colorsHex: ['FF00FF']), [
        '-d',
        '0',
        '-c',
        'FF00FF',
      ]);
    });
  });

  test(
    'missing OpenRGB is treated as no devices for native fallback',
    () async {
      final devices = await const OpenRgbCliService(
        executable: 'openrgb-executable-that-does-not-exist',
      ).listDevices();
      expect(devices, isEmpty);
    },
  );
}
