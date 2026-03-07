import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/boot_logo/models/boot_logo_status.dart';

void main() {
  group('BootLogoStatus.parseStatusOutput', () {
    test('parses ON with specific dimensions', () {
      final status = BootLogoStatus.parseStatusOutput(
        'Current Boot Logo status: ON; Required image dimensions: 1920 x 1080',
      );
      expect(status, isNotNull);
      expect(status!.isCustomEnabled, isTrue);
      expect(status.requiredWidth, equals(1920));
      expect(status.requiredHeight, equals(1080));
    });

    test('parses OFF with zero dimensions', () {
      final status = BootLogoStatus.parseStatusOutput(
        'Current Boot Logo status: OFF; Required image dimensions: 0 x 0',
      );
      expect(status, isNotNull);
      expect(status!.isCustomEnabled, isFalse);
      expect(status.requiredWidth, equals(0));
      expect(status.requiredHeight, equals(0));
    });

    test('returns null when output does not match expected format', () {
      expect(BootLogoStatus.parseStatusOutput(''), isNull);
      expect(BootLogoStatus.parseStatusOutput('Error: not found'), isNull);
    });

    test('hasDimensionConstraint is true when dimensions are non-zero', () {
      final status = BootLogoStatus(
        isCustomEnabled: false,
        requiredWidth: 1920,
        requiredHeight: 1080,
      );
      expect(status.hasDimensionConstraint, isTrue);
    });

    test('hasDimensionConstraint is false when both dimensions are zero', () {
      final status = BootLogoStatus(
        isCustomEnabled: false,
        requiredWidth: 0,
        requiredHeight: 0,
      );
      expect(status.hasDimensionConstraint, isFalse);
    });

    test('dimensionLabel returns WxH string when constrained', () {
      final status = BootLogoStatus(
        isCustomEnabled: true,
        requiredWidth: 800,
        requiredHeight: 600,
      );
      expect(status.dimensionLabel, equals('800×600'));
    });

    test('dimensionLabel returns "any" when unconstrained', () {
      final status = BootLogoStatus(
        isCustomEnabled: false,
        requiredWidth: 0,
        requiredHeight: 0,
      );
      expect(status.dimensionLabel, equals('any'));
    });
  });
}
