import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/lighting/models/rgb_lighting_device.dart';
import 'package:legion_frontend/features/lighting/repository/rgb_lighting_repository.dart';
import 'package:legion_frontend/features/lighting/services/openrgb_cli_service.dart';

/// Records the args passed to [apply] and returns canned [listDevices].
class _FakeService extends OpenRgbCliService {
  _FakeService(this._devices);

  final List<RgbLightingDevice> _devices;
  Map<String, Object?>? lastApply;

  @override
  Future<List<RgbLightingDevice>> listDevices() async => _devices;

  @override
  Future<void> apply({
    required int device,
    int? zone,
    String? mode,
    List<String>? colorsHex,
    int? brightness,
    int? speed,
  }) async {
    lastApply = {
      'device': device,
      'zone': zone,
      'mode': mode,
      'colorsHex': colorsHex,
      'brightness': brightness,
      'speed': speed,
    };
  }
}

const _kbd = RgbLightingDevice(
  index: 0,
  name: 'Legion KB',
  type: 'Keyboard',
  modes: ['Static', 'Direct'],
  leds: ['a', 'b'],
);

void main() {
  group('colorToOpenRgbHex', () {
    test('formats RRGGBB uppercase without #', () {
      expect(colorToOpenRgbHex(const Color(0xFFFFFFFF)), 'FFFFFF');
      expect(colorToOpenRgbHex(const Color(0xFF000000)), '000000');
      expect(colorToOpenRgbHex(const Color(0xFFFF0000)), 'FF0000');
      expect(colorToOpenRgbHex(const Color(0xFF1A2B3C)), '1A2B3C');
    });
  });

  group('RgbLightingRepository', () {
    test('loadKeyboard returns null when there are no devices', () async {
      final repo = RgbLightingRepository(service: _FakeService([]));
      expect(await repo.loadKeyboard(), isNull);
    });

    test('loadKeyboard picks the Keyboard-type device', () async {
      final repo = RgbLightingRepository(
        service: _FakeService([
          const RgbLightingDevice(index: 0, name: 'RAM', type: 'DRAM'),
          _kbd,
        ]),
      );
      expect((await repo.loadKeyboard())?.name, 'Legion KB');
    });

    test('applyMode sends device, mode, color and brightness', () async {
      final service = _FakeService([_kbd]);
      await RgbLightingRepository(service: service).applyMode(
        _kbd,
        'Static',
        color: const Color(0xFFFF0000),
        brightness: 80,
      );
      expect(service.lastApply, {
        'device': 0,
        'zone': null,
        'mode': 'Static',
        'colorsHex': ['FF0000'],
        'brightness': 80,
        'speed': null,
      });
    });

    test('applyDirect paints each LED via Direct mode', () async {
      final service = _FakeService([_kbd]);
      await RgbLightingRepository(
        service: service,
      ).applyDirect(_kbd, const [Color(0xFFFF0000), Color(0xFF00FF00)]);
      expect(service.lastApply!['mode'], 'Direct');
      expect(service.lastApply!['colorsHex'], ['FF0000', '00FF00']);
    });

    test('setBrightness sends only brightness, no mode', () async {
      final service = _FakeService([_kbd]);
      await RgbLightingRepository(service: service).setBrightness(_kbd, 50);
      expect(service.lastApply!['brightness'], 50);
      expect(service.lastApply!['mode'], isNull);
    });
  });
}
