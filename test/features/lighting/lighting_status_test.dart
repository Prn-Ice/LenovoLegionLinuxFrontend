import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/lighting/bloc/lighting_state.dart';
import 'package:legion_frontend/features/lighting/view/lighting_status.dart';

LightingState _state({
  bool kbdSupported = false,
  bool? kbdEnabled,
  bool yLogoSupported = false,
  bool? yLogoEnabled,
  bool ioSupported = false,
  bool? ioEnabled,
}) {
  return LightingState(
    whiteKeyboardBacklightEnabled: kbdEnabled,
    whiteKeyboardBacklightSupported: kbdSupported,
    yLogoLightEnabled: yLogoEnabled,
    yLogoLightSupported: yLogoSupported,
    ioPortLightEnabled: ioEnabled,
    ioPortLightSupported: ioSupported,
    isLoading: false,
  );
}

void main() {
  group('supportedZoneCount', () {
    test('counts only zones the device supports', () {
      expect(supportedZoneCount(_state()), 0);
      expect(supportedZoneCount(_state(kbdSupported: true)), 1);
      expect(
        supportedZoneCount(
          _state(kbdSupported: true, yLogoSupported: true, ioSupported: true),
        ),
        3,
      );
    });
  });

  group('activeZoneCount', () {
    test('counts supported zones that are on', () {
      expect(
        activeZoneCount(
          _state(
            kbdSupported: true,
            kbdEnabled: true,
            yLogoSupported: true,
            yLogoEnabled: false,
            ioSupported: true,
            ioEnabled: true,
          ),
        ),
        2,
      );
    });

    test('an unknown (null) zone state counts as off', () {
      expect(
        activeZoneCount(_state(kbdSupported: true, kbdEnabled: null)),
        0,
      );
    });

    test('ignores an enabled zone the device does not support', () {
      expect(activeZoneCount(_state(kbdSupported: false, kbdEnabled: true)), 0);
    });
  });

  group('lightingStatusLine', () {
    test('reports no controllable lighting when nothing is supported', () {
      expect(
        lightingStatusLine(_state()),
        'No controllable lighting on this device',
      );
    });

    test('reports all off', () {
      expect(
        lightingStatusLine(
          _state(
            kbdSupported: true,
            kbdEnabled: false,
            yLogoSupported: true,
            yLogoEnabled: false,
          ),
        ),
        'All lighting off',
      );
    });

    test('reports all zones on', () {
      expect(
        lightingStatusLine(
          _state(
            kbdSupported: true,
            kbdEnabled: true,
            yLogoSupported: true,
            yLogoEnabled: true,
          ),
        ),
        'All zones on',
      );
    });

    test('reports a single on zone', () {
      expect(
        lightingStatusLine(_state(kbdSupported: true, kbdEnabled: true)),
        'Lighting on',
      );
    });

    test('reports the on/total split when partially on', () {
      expect(
        lightingStatusLine(
          _state(
            kbdSupported: true,
            kbdEnabled: true,
            yLogoSupported: true,
            yLogoEnabled: false,
            ioSupported: true,
            ioEnabled: true,
          ),
        ),
        '2 of 3 zones on',
      );
    });
  });
}
