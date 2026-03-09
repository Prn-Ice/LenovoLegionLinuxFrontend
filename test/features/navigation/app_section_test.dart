import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/navigation/models/app_section.dart';

void main() {
  group('AppSection', () {
    test('has expected 11 values', () {
      expect(AppSection.values.length, 11);
    });

    test('contains new sections', () {
      expect(AppSection.values, contains(AppSection.devices));
      expect(AppSection.values, contains(AppSection.display));
      expect(AppSection.values, contains(AppSection.lighting));
      expect(AppSection.values, contains(AppSection.diagnostics));
    });

    test('does not contain removed sections', () {
      final names = AppSection.values.map((s) => s.name).toSet();
      expect(names, isNot(contains('displayLighting')));
      expect(names, isNot(contains('bootLogo')));
      expect(names, isNot(contains('analytics')));
      expect(names, isNot(contains('about')));
    });

    test('every section has a non-empty label', () {
      for (final section in AppSection.values) {
        expect(section.label, isNotEmpty, reason: 'Section ${section.name} has empty label');
      }
    });

    test('every section has a yaruIcon', () {
      for (final section in AppSection.values) {
        expect(section.yaruIcon, isNotNull);
      }
    });
  });
}
