import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:legion_frontend/features/lighting/models/rgb_lighting_device.dart';
import 'package:legion_frontend/features/lighting/providers/lighting_provider.dart';
import 'package:legion_frontend/features/lighting/services/openrgb_cli_service.dart';
import 'package:legion_frontend/features/lighting/services/spectrum_hid_service.dart';

import 'safe_app.dart';

/// Keeps RGB service calls inside the journey while preserving its real Bloc,
/// repositories, profile store, and app providers.
class SafeLighting {
  SafeLighting(SafeApp app)
    : _openRgb = _RecordingOpenRgb(),
      spectrum = SpectrumHidService(
        sysfsHidrawRoot: '${app.directory.path}/no-hidraw-devices',
        devRoot: '${app.directory.path}/no-devices',
      );

  final _RecordingOpenRgb _openRgb;
  final SpectrumHidService spectrum;

  List<Override> get overrides => [
    openRgbServiceProvider.overrideWithValue(_openRgb),
    spectrumHidServiceProvider.overrideWith((ref) {
      ref.onDispose(spectrum.close);
      return spectrum;
    }),
  ];

  List<List<String>> get writes => _openRgb.writes;
}

class _RecordingOpenRgb extends OpenRgbCliService {
  final writes = <List<String>>[];

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<List<RgbLightingDevice>> listDevices() async => const [
    RgbLightingDevice(
      index: 0,
      name: 'Journey keyboard',
      type: 'Keyboard',
      modes: ['Direct', 'Static'],
      activeMode: 'Direct',
      leds: ['Key 1', 'Key 2', 'Key 3'],
    ),
  ];

  @override
  Future<void> apply({
    required int device,
    int? zone,
    String? mode,
    List<String>? colorsHex,
    int? brightness,
    int? speed,
  }) async {
    writes.add(List.unmodifiable(colorsHex ?? const []));
  }
}
