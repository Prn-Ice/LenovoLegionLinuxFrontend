import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/navigation/models/app_section.dart';
import 'package:legion_frontend/features/navigation/models/nav_entry.dart';

void main() {
  group('NavEntry', () {
    test('NavHeader stores title', () {
      const header = NavHeader('PERFORMANCE');
      expect(header.title, 'PERFORMANCE');
    });

    test('NavPageEntry stores section', () {
      const entry = NavPageEntry(AppSection.power);
      expect(entry.section, AppSection.power);
    });

    test('sealed class exhaustiveness: switch compiles', () {
      const NavEntry entry = NavPageEntry(AppSection.dashboard);
      final result = switch (entry) {
        NavHeader h => h.title,
        NavPageEntry p => p.section.name,
      };
      expect(result, 'dashboard');
    });
  });

  group('NavShellEntries', () {
    test('contains 4 headers', () {
      final headers = NavShellEntries.all.whereType<NavHeader>().toList();
      expect(headers.length, 4);
    });

    test('contains 11 page entries', () {
      final pages = NavShellEntries.all.whereType<NavPageEntry>().toList();
      expect(pages.length, 11);
    });

    test('all AppSection values are represented', () {
      final sections = NavShellEntries.all
          .whereType<NavPageEntry>()
          .map((e) => e.section)
          .toSet();
      expect(sections, containsAll(AppSection.values));
    });

    test('indexFor returns correct position including headers', () {
      final idx = NavShellEntries.indexFor(AppSection.dashboard);
      expect(idx, 0); // Dashboard is first entry, no headers before it
    });

    test('indexFor returns correct position: power is at index 2', () {
      // Dashboard at 0, PERFORMANCE header at 1, power at 2
      final idx = NavShellEntries.indexFor(AppSection.power);
      expect(idx, 2);
    });
  });
}
