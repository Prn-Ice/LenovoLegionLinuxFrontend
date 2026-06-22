import '../bloc/lighting_state.dart';

/// Number of coarse backlight zones (white keyboard, Y-logo, IO-port) the
/// device actually supports.
int supportedZoneCount(LightingState s) =>
    (s.whiteKeyboardBacklightSupported ? 1 : 0) +
    (s.yLogoLightSupported ? 1 : 0) +
    (s.ioPortLightSupported ? 1 : 0);

/// Number of supported backlight zones currently switched on.
int activeZoneCount(LightingState s) =>
    (s.whiteKeyboardBacklightSupported &&
            (s.whiteKeyboardBacklightEnabled ?? false)
        ? 1
        : 0) +
    (s.yLogoLightSupported && (s.yLogoLightEnabled ?? false) ? 1 : 0) +
    (s.ioPortLightSupported && (s.ioPortLightEnabled ?? false) ? 1 : 0);

/// A short human summary of the backlight zones for the page hero.
String lightingStatusLine(LightingState s) {
  final total = supportedZoneCount(s);
  if (total == 0) return 'No controllable lighting on this device';
  final on = activeZoneCount(s);
  if (on == 0) return 'All lighting off';
  if (on == total) return total == 1 ? 'Lighting on' : 'All zones on';
  return '$on of $total zones on';
}
