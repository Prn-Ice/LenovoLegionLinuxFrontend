import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/lighting/view/lighting_page.dart';

void main() {
  test('native probe failures do not suggest starting OpenRGB', () {
    final message = rgbUnavailableMessage(
      nativeAvailabilityError: 'hidraw probe failed',
    );

    expect(message, contains('Native Spectrum RGB is unavailable'));
    expect(message, isNot(contains('Start OpenRGB')));
  });

  test('missing native device retains the OpenRGB fallback guidance', () {
    expect(rgbUnavailableMessage(), contains('Start OpenRGB'));
  });
}
