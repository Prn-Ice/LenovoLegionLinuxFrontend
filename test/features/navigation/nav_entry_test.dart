import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/navigation/models/app_section.dart';
import 'package:legion_frontend/features/navigation/models/nav_entry.dart';

void main() {
  group('NavShellEntries', () {
    test('is a flat list led by the dashboard', () {
      expect(NavShellEntries.sections.first, AppSection.dashboard);
      expect(NavShellEntries.sections, contains(AppSection.lighting));
    });

    test('has every section exactly once', () {
      expect(
        NavShellEntries.sections.toSet().length,
        NavShellEntries.sections.length,
      );
      expect(NavShellEntries.sections.length, AppSection.values.length);
    });

    test('indexFor returns the position in the flat list', () {
      expect(NavShellEntries.indexFor(AppSection.dashboard), 0);
      expect(
        NavShellEntries.indexFor(NavShellEntries.sections.last),
        NavShellEntries.sections.length - 1,
      );
    });
  });
}
