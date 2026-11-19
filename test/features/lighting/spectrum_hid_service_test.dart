import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/lighting/services/spectrum_hid_service.dart';
import 'package:legion_frontend/features/lighting/services/spectrum_protocol.dart';

import '../../support/recording_spectrum_hid_io.dart';

void main() {
  test('discovers the supported device and records protocol reports', () async {
    final root = await Directory.systemTemp.createTemp('spectrum_hid_test_');
    addTearDown(() => root.delete(recursive: true));
    final hidraw = Directory('${root.path}/hidraw0/device');
    await hidraw.create(recursive: true);
    await File('${hidraw.path}/uevent')
        .writeAsString('HID_ID=0003:0000048D:0000C987\n');
    final io = RecordingSpectrumHidIo();
    final service = SpectrumHidService(
      sysfsHidrawRoot: root.path,
      devRoot: '${root.path}/dev',
      io: io,
    );

    expect(service.inspectHidraw().outcome.name, 'supported');
    expect(service.open(), isTrue);
    expect(
      service.sendDirectFrame(const [SpectrumLed(0x1234, 0x11, 0x22, 0x33)]),
      isTrue,
    );
    service.close();

    expect(io.closeCount, 1);
    expect(io.reports, hasLength(5));
    expect(io.reports[0].sublist(0, 4), [7, 0xca, 0xc0, 3]);
    expect(io.reports[1].sublist(0, 4), [7, 0xca, 0xc0, 3]);
    expect(io.reports[2].sublist(0, 6), [7, 0xd0, 0xc0, 3, 1, 2]);
    expect(io.reports[3].sublist(0, 6), [7, 0xcb, 28, 3, 2, 1]);
    expect(io.reports[4].sublist(0, 4), [7, 0xa1, 0xc0, 3]);
    expect(io.reports[4].sublist(4, 9), [0x34, 0x12, 0x11, 0x22, 0x33]);
  });

  test(
    'sendDirectFrame returns false when a feature report is rejected',
    () async {
      final root = await Directory.systemTemp.createTemp('spectrum_hid_test_');
      addTearDown(() => root.delete(recursive: true));
      final hidraw = Directory('${root.path}/hidraw0/device');
      await hidraw.create(recursive: true);
      await File('${hidraw.path}/uevent')
          .writeAsString('HID_ID=0003:0000048D:0000C987\n');
      final service = SpectrumHidService(
        sysfsHidrawRoot: root.path,
        devRoot: '${root.path}/dev',
        io: RecordingSpectrumHidIo(ioctlResult: -1),
      );
      addTearDown(service.close);

      expect(service.sendDirectFrame(const [SpectrumLed(1, 1, 2, 3)]), isFalse);
    },
  );
}
