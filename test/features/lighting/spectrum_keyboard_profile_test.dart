import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/lighting/models/spectrum_keyboard_profile.dart';
import 'package:legion_frontend/features/lighting/models/spectrum_hid_discovery.dart';
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
      expect(
        service.inspectHidraw().outcome,
        SpectrumHidDiscoveryOutcome.rootMissing,
      );
      addDevice('hidraw0', _fixture('unknown-product'));
      expect(service.findHidrawPath(), isNull);
      expect(
        service.inspectHidraw().outcome,
        SpectrumHidDiscoveryOutcome.missing,
      );
      expect(
        service.inspectHidraw().attempts.single.outcome,
        SpectrumHidDiscoveryOutcome.unsupported,
      );
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
        final discovery = service.inspectHidraw();
        expect(discovery.outcome, SpectrumHidDiscoveryOutcome.supported);
        expect(discovery.vendorId, kSpectrumVendorId);
        expect(discovery.productId, kSpectrumC987ProductId);
        expect(discovery.protocol, SpectrumProtocol.gen7And8);
        expect(
          discovery.toJson()['selected_hidraw_path'],
          '<custom-dev-root>/hidraw3',
        );
        expect(discovery.attempts.map((attempt) => attempt.hidrawName), [
          'hidraw0',
          'hidraw1',
          'hidraw2',
          'hidraw3',
        ]);
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

    test('reports malformed identity without opening a device', () {
      addDevice('hidraw0', 'HID_ID=not-an-id\n');
      final discovery = service.inspectHidraw();
      expect(discovery.outcome, SpectrumHidDiscoveryOutcome.malformed);
      expect(discovery.selectedHidrawPath, isNull);
      expect(service.isOpen, isFalse);
    });

    test('reports a non-directory root as unreadable', () {
      File('${root.path}/sys').writeAsStringSync('not a directory');
      expect(
        service.inspectHidraw().outcome,
        SpectrumHidDiscoveryOutcome.rootUnreadable,
      );
    });

    test('unexpected root failure remains unknown', () {
      Link('${root.path}/sys').createSync('${root.path}/sys');
      expect(
        service.inspectHidraw().outcome,
        SpectrumHidDiscoveryOutcome.unknown,
      );
    });

    test('exports normal device path and ignores non-hidraw entries', () {
      addDevice('PRIVATE-NAME', _fixture('c987'));
      addDevice('hidraw4', _fixture('c987'));
      final standardDev = SpectrumHidService(
        sysfsHidrawRoot: '${root.path}/sys',
      );
      final discovery = standardDev.inspectHidraw();
      expect(discovery.selectedHidrawPath, '/dev/hidraw4');
      expect(discovery.toJson()['selected_hidraw_path'], '/dev/hidraw4');
      expect(discovery.attempts.single.hidrawName, 'hidraw4');
      expect(discovery.toJson().toString(), isNot(contains('PRIVATE-NAME')));
      expect(standardDev.isOpen, isFalse);
    });

    test('reports invalid UTF-8 without aborting discovery', () {
      final device = Directory('${root.path}/sys/hidraw0/device')
        ..createSync(recursive: true);
      File('${device.path}/uevent').writeAsBytesSync([0xff, 0xfe]);
      final discovery = service.inspectHidraw();
      expect(discovery.outcome, SpectrumHidDiscoveryOutcome.malformedUtf8);
      expect(
        discovery.attempts.single.outcome,
        SpectrumHidDiscoveryOutcome.malformedUtf8,
      );
      expect(service.isOpen, isFalse);
    });

    test(
      'unknown configured ID stays unsupported while known device is reported',
      () {
        addDevice('hidraw0', _fixture('c987'));
        final unknown = SpectrumHidService(
          vendorId: 0x048d,
          productId: 0xc988,
          sysfsHidrawRoot: '${root.path}/sys',
          devRoot: '${root.path}/dev',
        );
        final discovery = unknown.inspectHidraw();
        expect(discovery.outcome, SpectrumHidDiscoveryOutcome.unsupported);
        expect(
          discovery.attempts.single.outcome,
          SpectrumHidDiscoveryOutcome.supported,
        );
        expect(discovery.selectedHidrawPath, isNull);
        expect(unknown.isOpen, isFalse);
      },
    );
  });
}
