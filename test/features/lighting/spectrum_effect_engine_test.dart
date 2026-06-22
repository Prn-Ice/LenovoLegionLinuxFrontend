import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/lighting/repository/spectrum_rgb_repository.dart';
import 'package:legion_frontend/features/lighting/services/spectrum_effect_engine.dart';
import 'package:legion_frontend/features/lighting/services/spectrum_effects.dart';
import 'package:legion_frontend/features/lighting/services/spectrum_hid_service.dart';
import 'package:legion_frontend/features/lighting/services/spectrum_protocol.dart';

class _FakeService extends SpectrumHidService {
  List<SpectrumLed>? lastFrame;

  @override
  String? findHidrawPath() => '/dev/hidraw0';

  @override
  bool sendDirectFrame(List<SpectrumLed> leds) {
    lastFrame = leds;
    return true;
  }
}

void main() {
  test('runs only while effects are assigned', () {
    final engine = SpectrumEffectEngine(
      SpectrumRgbRepository(service: _FakeService()),
    );
    expect(engine.isRunning, isFalse);

    engine.configure(
      base: const [],
      leds: const [],
      effects: const [
        SpectrumRegionEffect(
          ledIndices: [0],
          effect: SpectrumEffect.pulse,
          color: Color(0xFFFF0000),
        ),
      ],
    );
    expect(engine.isRunning, isTrue);

    engine.configure(base: const [], leds: const [], effects: const []);
    expect(engine.isRunning, isFalse);
    expect(engine.frame.value, isNull);

    engine.dispose();
  });
}
