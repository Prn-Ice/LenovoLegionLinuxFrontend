import 'app_section.dart';

sealed class NavEntry {
  const NavEntry();
}

final class NavHeader extends NavEntry {
  const NavHeader(this.title);
  final String title;
}

final class NavPageEntry extends NavEntry {
  const NavPageEntry(this.section);
  final AppSection section;
}

/// The canonical ordered list of all navigation entries for the wide sidebar.
/// Headers are non-selectable labels. Order matches the design spec.
abstract final class NavShellEntries {
  static const List<NavEntry> all = [
    NavPageEntry(AppSection.dashboard),
    NavHeader('PERFORMANCE'),
    NavPageEntry(AppSection.power),
    NavPageEntry(AppSection.fans),
    NavHeader('HARDWARE'),
    NavPageEntry(AppSection.battery),
    NavPageEntry(AppSection.devices),
    NavPageEntry(AppSection.dgpu),
    NavHeader('DISPLAY'),
    NavPageEntry(AppSection.display),
    NavPageEntry(AppSection.lighting),
    NavHeader('SYSTEM'),
    NavPageEntry(AppSection.automation),
    NavPageEntry(AppSection.settings),
    NavPageEntry(AppSection.diagnostics),
  ];

  /// All selectable sections in order, for the narrow rail layout.
  static final List<AppSection> pages = all
      .whereType<NavPageEntry>()
      .map((e) => e.section)
      .toList(growable: false);

  /// Controller index for [section] in the full [all] list (including headers).
  /// Returns -1 if not found (should never happen in practice).
  static int indexFor(AppSection section) {
    return all.indexWhere(
      (e) => e is NavPageEntry && e.section == section,
    );
  }

  /// Narrow-rail index for [section] (headers excluded).
  static int narrowIndexFor(AppSection section) {
    return pages.indexOf(section);
  }
}
