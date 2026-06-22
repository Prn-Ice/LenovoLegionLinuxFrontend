import 'app_section.dart';

/// The flat, ordered list of navigation sections for the sidebar and rail.
/// Matches the design: a single list with no section-group headers.
abstract final class NavShellEntries {
  static const List<AppSection> sections = [
    AppSection.dashboard,
    AppSection.power,
    AppSection.fans,
    AppSection.battery,
    AppSection.devices,
    AppSection.dgpu,
    AppSection.display,
    AppSection.lighting,
    AppSection.automation,
    AppSection.settings,
    AppSection.diagnostics,
  ];

  /// Index of [section] within [sections] (-1 if absent).
  static int indexFor(AppSection section) => sections.indexOf(section);
}
