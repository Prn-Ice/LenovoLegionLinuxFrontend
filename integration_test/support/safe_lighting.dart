import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:legion_frontend/features/lighting/providers/lighting_provider.dart';
import 'package:legion_frontend/features/lighting/services/openrgb_cli_service.dart';
import 'package:legion_frontend/features/lighting/services/spectrum_hid_service.dart';

import 'safe_app.dart';

/// Supplies OpenRGB process results without running commands or opening HID.
/// The journey uses the real service, repositories, Bloc, and profile store.
class SafeLighting {
  SafeLighting(SafeApp app)
    : spectrum = SpectrumHidService(
        sysfsHidrawRoot: '${app.directory.path}/no-hidraw-devices',
        devRoot: '${app.directory.path}/no-devices',
      );

  late final _openRgb = OpenRgbCliService(processRunner: _run);
  final SpectrumHidService spectrum;
  final writes = <List<String>>[];
  final requests = <List<String>>[];
  int? nextExitCode;
  Completer<void>? writeCompletion;

  List<Override> get overrides => [
    openRgbServiceProvider.overrideWithValue(_openRgb),
    spectrumHidServiceProvider.overrideWith((ref) {
      ref.onDispose(spectrum.close);
      return spectrum;
    }),
  ];

  Future<ProcessResult> _run(String executable, List<String> arguments) async {
    if (arguments.length == 1 && arguments.single == '--list-devices') {
      return ProcessResult(1, 0, '''0: Journey keyboard
Type: Keyboard
Modes: [Direct] Static
LEDs: 'Key 1' 'Key 2' 'Key 3'
''', '');
    }
    if (arguments.length < 2 || arguments[0] != '-d' || arguments[1] != '0') {
      throw StateError('Unexpected OpenRGB command: $executable $arguments');
    }
    requests.add(List.unmodifiable(arguments));
    final exitCode = nextExitCode ?? 0;
    nextExitCode = null;
    await writeCompletion?.future;
    if (exitCode != 0) {
      return ProcessResult(
        1,
        exitCode,
        'Test command started',
        'Test device rejected the write',
      );
    }
    final colorFlag = arguments.indexOf('-c');
    writes.add(colorFlag < 0 ? const [] : arguments[colorFlag + 1].split(','));
    return ProcessResult(1, 0, '', '');
  }
}
