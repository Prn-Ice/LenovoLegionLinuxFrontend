import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/services/xrandr_service.dart';

const _singleEdpOutput = '''
Screen 0: minimum 320 x 200, current 1920 x 1080, maximum 16384 x 16384
eDP-1 connected primary 1920x1080+0+0 (normal left inverted right x axis y axis) 340mm x 190mm
   1920x1080     60.00*+  120.00   144.00
   1280x720      60.00
HDMI-1 disconnected (normal left inverted right x axis y axis)
''';

const _edpAtHighRate = '''
Screen 0: minimum 320 x 200, current 1920 x 1080, maximum 16384 x 16384
eDP-1 connected primary 1920x1080+0+0 (normal left inverted right x axis y axis) 340mm x 190mm
   1920x1080     60.00+   120.00   144.00*
''';

const _noConnectedEdp = '''
Screen 0: minimum 320 x 200, current 1920 x 1080, maximum 16384 x 16384
eDP-1 disconnected (normal left inverted right x axis y axis)
HDMI-1 connected 1920x1080+0+0 (normal left inverted right x axis y axis) 530mm x 300mm
   1920x1080     60.00*+
''';

const _emptyOutput = '';

void main() {
  group('XrandrService.parseOutput', () {
    test('parses eDP-1 with multiple rates and identifies current rate', () {
      final info = XrandrService.parseOutput(_singleEdpOutput);
      expect(info, isNotNull);
      expect(info!.outputName, equals('eDP-1'));
      expect(info.currentRate, equals(60.0));
      expect(info.availableRates, containsAll([60.0, 120.0, 144.0]));
      expect(info.availableRates.length, equals(3));
    });

    test('identifies current rate at higher value', () {
      final info = XrandrService.parseOutput(_edpAtHighRate);
      expect(info, isNotNull);
      expect(info!.currentRate, equals(144.0));
      expect(info.availableRates, containsAll([60.0, 120.0, 144.0]));
    });

    test('returns null when no eDP output is connected', () {
      final info = XrandrService.parseOutput(_noConnectedEdp);
      expect(info, isNull);
    });

    test('returns null for empty output', () {
      final info = XrandrService.parseOutput(_emptyOutput);
      expect(info, isNull);
    });
  });
}
