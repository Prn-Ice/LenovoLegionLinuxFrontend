import 'dart:io';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:legion_frontend/features/lighting/providers/lighting_provider.dart';
import 'package:legion_frontend/features/lighting/services/spectrum_hid_service.dart';
import 'package:legion_frontend/features/lighting/services/openrgb_cli_service.dart';

import 'safe_app.dart';
import '../../test/support/recording_spectrum_hid_io.dart';

/// Keeps native Spectrum discovery and report construction real while replacing
/// only libc HID calls with a recording fixture inside the app directory.
final class SafeSpectrum {
  SafeSpectrum._(this.service, this.io);

  final SpectrumHidService service;
  final RecordingSpectrumHidIo io;
  final openRgbProbes = <List<String>>[];

  static Future<SafeSpectrum> create(SafeApp app) async {
    final root = Directory('${app.directory.path}/sys/class/hidraw');
    final uevent = Directory('${root.path}/hidraw0/device');
    await uevent.create(recursive: true);
    await File('${uevent.path}/uevent')
        .writeAsString('HID_ID=0003:0000048D:0000C987\n');
    final io = RecordingSpectrumHidIo();
    return SafeSpectrum._(
      SpectrumHidService(
        sysfsHidrawRoot: root.path,
        devRoot: '${app.directory.path}/dev',
        io: io,
      ),
      io,
    );
  }

  List<Override> get overrides => [
    openRgbServiceProvider.overrideWithValue(
      OpenRgbCliService(
        processRunner: (_, arguments) async {
          openRgbProbes.add(List.unmodifiable(arguments));
          if (arguments.length == 1 && arguments.single == '--list-devices') {
            return ProcessResult(
              0,
              1,
              '',
              'OpenRGB is absent in the native fixture',
            );
          }
          throw StateError('Native Spectrum must not run OpenRGB: $arguments');
        },
      ),
    ),
    spectrumHidServiceProvider.overrideWith((ref) {
      ref.onDispose(service.close);
      return service;
    }),
  ];
}
