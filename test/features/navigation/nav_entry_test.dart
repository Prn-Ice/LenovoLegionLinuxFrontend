import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/navigation/models/app_section.dart';
import 'package:legion_frontend/features/navigation/models/nav_entry.dart';

void main() {
  group('NavShellEntries', () {
    test('is a flat list led by the dashboard', () {
      expect(NavShellEntries.sections.first, AppSection.dashboard);
      expect(NavShellEntries.sections, [
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

    test('has every section exactly once', () {
      expect(
        NavShellEntries.sections.toSet().length,
        NavShellEntries.sections.length,
      );
      expect(NavShellEntries.sections.length, AppSection.values.length);
    });

    test('indexFor maps every section for both shell layouts', () {
      // Compact and wide layouts both build destinations from this shared list.
      for (var index = 0; index < NavShellEntries.sections.length; index++) {
        expect(
          NavShellEntries.indexFor(NavShellEntries.sections[index]),
          index,
        );
      }
      expect(NavShellEntries.indexFor(AppSection.lighting), 4);
      expect(NavShellEntries.indexFor(AppSection.dgpu), 5);
      expect(NavShellEntries.indexFor(AppSection.settings), 7);
    });
  });
}
