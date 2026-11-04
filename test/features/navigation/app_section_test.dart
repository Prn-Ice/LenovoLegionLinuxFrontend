import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/navigation/models/app_section.dart';

void main() {
  group('AppSection', () {
    test('contains only top-level destinations in stable order', () {
      expect(AppSection.values, [
        AppSection.dashboard,
        AppSection.power,
        AppSection.fans,
        AppSection.battery,
        AppSection.lighting,
        AppSection.dgpu,
        AppSection.automation,
        AppSection.settings,
      ]);
    });

    test('every section has a non-empty label', () {
      for (final section in AppSection.values) {
        expect(
          section.label,
          isNotEmpty,
          reason: 'Section ${section.name} has empty label',
        );
      }
    });
  });
}
