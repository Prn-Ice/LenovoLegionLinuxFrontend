import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/lighting/models/spectrum_keyboard_profile.dart';
import 'package:legion_frontend/features/lighting/services/spectrum_hid_service.dart';

String _fixture(String name) =>
    File('test/fixtures/lighting/spectrum/$name.uevent').readAsStringSync();

void main() {
  test('matches supported IDs regardless of hex case and padding', () {
    expect(
      spectrumKeyboardProfileFromUevent(_fixture('c987')),
      same(kSpectrumC987Profile),
    );
    expect(
      spectrumKeyboardProfileFromUevent('HID_ID=0003:048d:c987\r\n'),
      same(kSpectrumC987Profile),
    );
  });

  test(
    'same vendor/name, wrong vendor, and malformed identity stay unknown',
    () {
      for (final uevent in [
        _fixture('unknown-product'),
        'HID_ID=0003:0000048E:0000C987\n',
        'HID_NAME=Legion Spectrum Keyboard\n',
        'HID_ID=0003:048d:c987suffix\n',
        'NOT_HID_ID=0003:048d:c987\n',
        'HID_ID=0003:048d:\n',
        'HID_ID=garbage\n',
      ]) {
        expect(
          spectrumKeyboardProfileFromUevent(uevent),
          isNull,
          reason: uevent,
        );
      }
    },
  );

  test(
    'supported data has unique identities and valid preview LED addresses',
    () {
      final identities = <(int, int)>{};
      for (final profile in kSupportedSpectrumKeyboards) {
        expect(identities.add((profile.vendorId, profile.productId)), isTrue);
        expect(profile.protocol, SpectrumProtocol.gen7And8);
        expect(
          profile.ledValues.values.toSet().length,
          profile.ledValues.length,
        );
        expect(
          profile.ledValues.values,
          everyElement(inInclusiveRange(1, 65535)),
        );
        final layoutNames = [
          for (final row in profile.layout.rows)
            for (final cap in [...row.main, ...row.nav, ...row.numpad])
              if (!cap.isGap) cap.led,
          ...profile.layout.neonLeds,
        ];
        expect(layoutNames.toSet(), profile.ledValues.keys.toSet());
        expect(layoutNames.toSet().length, layoutNames.length);
      }
    },
  );

  group('read-only hidraw discovery', () {
    late Directory root;
    late SpectrumHidService service;

    setUp(() {
      root = Directory.systemTemp.createTempSync('spectrum-discovery-');
      service = SpectrumHidService(
        sysfsHidrawRoot: '${root.path}/sys',
        devRoot: '${root.path}/dev',
      );
    });
    tearDown(() => root.deleteSync(recursive: true));

    void addDevice(String name, String uevent) {
      final device = Directory('${root.path}/sys/$name/device');
      device.createSync(recursive: true);
      File('${device.path}/uevent').writeAsStringSync(uevent);
    }

    test('missing root and unknown device return no path', () {
      expect(service.findHidrawPath(), isNull);
      addDevice('hidraw0', _fixture('unknown-product'));
      expect(service.findHidrawPath(), isNull);
    });

    test(
      'skips missing/malformed uevents and selects the exact supported ID',
      () {
        addDevice('hidraw0', _fixture('unknown-product'));
        addDevice('hidraw1', 'HID_ID=not-an-id\n');
        Directory(
          '${root.path}/sys/hidraw2/device',
        ).createSync(recursive: true);
        addDevice('hidraw3', _fixture('c987'));

        expect(service.findHidrawPath(), '${root.path}/dev/hidraw3');
        expect(service.isOpen, isFalse);
        expect(Directory('${root.path}/dev').existsSync(), isFalse);
      },
    );

    test('explicit unknown target cannot opt into the Gen7/8 transport', () {
      addDevice('hidraw0', _fixture('unknown-product'));
      final unknown = SpectrumHidService(
        productId: 0xC988,
        sysfsHidrawRoot: '${root.path}/sys',
        devRoot: '${root.path}/dev',
      );
      expect(unknown.keyboardProfile, isNull);
      expect(unknown.findHidrawPath(), isNull);
      expect(unknown.isOpen, isFalse);
    });
  });
}
