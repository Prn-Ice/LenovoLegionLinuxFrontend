****# UI Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Redesign the app into a living control centre — grouped sidebar, rich dashboard with live sensors and device identity, `AppControlCard` feature pages, split blocs for Display/Lighting and Battery/Devices, merged Diagnostics page.

**Architecture:** Phase 1 (Tasks 1–4) builds the structural foundation: new AppSection enum, NavEntry sealed class, NavigationShell update, and shared card widgets. Phase 2 (Tasks 5–6) builds the live sensor infrastructure. Phase 3 (Tasks 7–9) completes the dashboard. Phase 4 (Tasks 10–11) splits the two existing blocs. Phase 5 (Tasks 12–21) rebuilds each feature page. Every task ends with a commit and `flutter test` green.

**Tech Stack:** Flutter, Yaru (≥9.0.1), flutter_riverpod, riverbloc, equatable, fl_chart (already in pubspec), mocktail, bloc_test.

**Design reference:** `docs/plans/2026-03-09-ui-redesign-design.md`

---

## Phase 1 — Structural Foundation

### Task 1: Extend AppSection enum

**Files:**
- Modify: `lib/features/navigation/models/app_section.dart`
- Modify any tests that reference removed enum values

**Context:** The current enum has 11 values. We remove `displayLighting`, `bootLogo`, `analytics`, `about` and add `devices`, `display`, `lighting`, `diagnostics`. Net result is still 11 values but in a new order.

**Step 1: Write the failing test**

`test/features/navigation/app_section_test.dart`

```dart
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
      // These should fail to compile after the change — verify by name
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
```

**Step 2: Run test to confirm it fails**

```bash
cd /home/prnice/Projects/personal/LenovoLegionLinuxFrontend
flutter test test/features/navigation/app_section_test.dart -v
```

Expected: compile errors or test failures because `devices`, `display`, `lighting`, `diagnostics` don't exist yet.

**Step 3: Rewrite `lib/features/navigation/models/app_section.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

enum AppSection {
  dashboard,
  power,
  fans,
  battery,
  devices,
  dgpu,
  display,
  lighting,
  automation,
  settings,
  diagnostics,
}

extension AppSectionUi on AppSection {
  String get label {
    switch (this) {
      case AppSection.dashboard:
        return 'Dashboard';
      case AppSection.power:
        return 'Power';
      case AppSection.fans:
        return 'Fans';
      case AppSection.battery:
        return 'Battery';
      case AppSection.devices:
        return 'Devices';
      case AppSection.dgpu:
        return 'Discrete GPU';
      case AppSection.display:
        return 'Display';
      case AppSection.lighting:
        return 'Lighting';
      case AppSection.automation:
        return 'Automation';
      case AppSection.settings:
        return 'Settings';
      case AppSection.diagnostics:
        return 'Diagnostics';
    }
  }

  IconData get icon {
    switch (this) {
      case AppSection.dashboard:
        return Icons.dashboard_outlined;
      case AppSection.power:
        return Icons.bolt_outlined;
      case AppSection.fans:
        return Icons.air_outlined;
      case AppSection.battery:
        return Icons.battery_charging_full_outlined;
      case AppSection.devices:
        return Icons.devices_outlined;
      case AppSection.dgpu:
        return Icons.memory_outlined;
      case AppSection.display:
        return Icons.monitor_outlined;
      case AppSection.lighting:
        return Icons.light_mode_outlined;
      case AppSection.automation:
        return Icons.auto_mode_outlined;
      case AppSection.settings:
        return Icons.settings_outlined;
      case AppSection.diagnostics:
        return Icons.analytics_outlined;
    }
  }

  IconData get yaruIcon {
    switch (this) {
      case AppSection.dashboard:
        return YaruIcons.chip;
      case AppSection.power:
        return YaruIcons.thunderbolt;
      case AppSection.fans:
        return YaruIcons.gears;
      case AppSection.battery:
        return YaruIcons.battery_full_charging;
      case AppSection.devices:
        return YaruIcons.input_keyboard;
      case AppSection.dgpu:
        return YaruIcons.chip;
      case AppSection.display:
        return YaruIcons.display_layout;
      case AppSection.lighting:
        return YaruIcons.color_select;
      case AppSection.automation:
        return YaruIcons.gear_dots;
      case AppSection.settings:
        return YaruIcons.gear;
      case AppSection.diagnostics:
        return YaruIcons.monitor;
    }
  }
}
```

**Step 4: Fix compile errors in other files**

Any file that references `AppSection.displayLighting`, `AppSection.bootLogo`, `AppSection.analytics`, or `AppSection.about` will now fail to compile. Find them:

```bash
grep -r "AppSection\.\(displayLighting\|bootLogo\|analytics\|about\)" \
  lib/ test/ --include="*.dart" -l
```

For each file found:
- References to `AppSection.displayLighting` → `AppSection.display` (temporary; full split in Task 10)
- References to `AppSection.analytics` → `AppSection.diagnostics` (temporary; full merge in Task 21)
- References to `AppSection.about` → `AppSection.diagnostics`
- References to `AppSection.bootLogo` → `AppSection.settings`

**Step 5: Run tests**

```bash
flutter test -v
```

Expected: All pass. If NavigationShell fails, fix by updating any `.index` usage that assumed old enum order (full NavigationShell rewrite is Task 3).

**Step 6: Commit**

```bash
git add lib/features/navigation/models/app_section.dart \
        test/features/navigation/app_section_test.dart
git add -u  # stage any files modified in step 4
git commit -m "feat(nav): restructure AppSection enum — add devices/display/lighting/diagnostics"
```

---

### Task 2: Create NavEntry sealed class

**Files:**
- Create: `lib/features/navigation/models/nav_entry.dart`
- Create: `test/features/navigation/nav_entry_test.dart`

**Context:** `NavEntry` is a sealed class with two subtypes: `NavHeader` (non-selectable sidebar label) and `NavPageEntry` (selectable page). The `NavigationShell` will use a `List<NavEntry>` instead of `AppSection.values`.

**Step 1: Write the failing test**

```dart
// test/features/navigation/nav_entry_test.dart
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

    test('indexFor returns -1 for unknown section', () {
      // All sections are present so this is defensive only
      // Verify power is at index 2 (after Dashboard at 0, PERFORMANCE header at 1)
      final idx = NavShellEntries.indexFor(AppSection.power);
      expect(idx, 2);
    });
  });
}
```

**Step 2: Run test to verify it fails**

```bash
flutter test test/features/navigation/nav_entry_test.dart -v
```

Expected: compile error — `NavEntry`, `NavHeader`, `NavPageEntry`, `NavShellEntries` not found.

**Step 3: Create `lib/features/navigation/models/nav_entry.dart`**

```dart
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
```

**Step 4: Run tests**

```bash
flutter test test/features/navigation/nav_entry_test.dart -v
```

Expected: All pass.

**Step 5: Commit**

```bash
git add lib/features/navigation/models/nav_entry.dart \
        test/features/navigation/nav_entry_test.dart
git commit -m "feat(nav): add NavEntry sealed class with grouped sidebar entries"
```

---

### Task 3: Update NavigationShell with grouped sidebar

**Files:**
- Modify: `lib/features/navigation/view/navigation_shell.dart`

**Context:** Replace `AppSection.values` flat list with `NavShellEntries.all`. The wide `YaruMasterDetailPage` renders headers as muted labels; the narrow `YaruNavigationPage` skips headers entirely. `YaruPageController` length = `NavShellEntries.all.length` (15). `onSelected` ignores header indices. The mapping from `AppSection` to controller index uses `NavShellEntries.indexFor()`.

Two controllers are needed:
- `_wideController` — length 15, includes headers
- `_narrowController` — length 11, pages only

**Step 1: No test to write first** — `NavigationShell` is a `ConsumerStatefulWidget` and best tested visually. Verify by running the app and confirming grouped sidebar renders.

**Step 2: Rewrite `lib/features/navigation/view/navigation_shell.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../about/view/about_page.dart';
import '../../analytics/view/analytics_page.dart';
import '../../automation/view/automation_page.dart';
import '../../battery_devices/view/battery_devices_page.dart';
import '../../boot_logo/view/boot_logo_page.dart';
import '../../dashboard/view/dashboard_page.dart';
import '../../dgpu/view/dgpu_page.dart';
import '../../display_lighting/view/display_lighting_page.dart';
import '../../fans/view/fans_page.dart';
import '../../power/view/power_page.dart';
import '../../settings/view/settings_page.dart';
import '../bloc/navigation_event.dart';
import '../models/app_section.dart';
import '../models/nav_entry.dart';
import '../providers/navigation_provider.dart';

class NavigationShell extends ConsumerStatefulWidget {
  const NavigationShell({super.key});

  @override
  ConsumerState<NavigationShell> createState() => _NavigationShellState();
}

class _NavigationShellState extends ConsumerState<NavigationShell> {
  late final YaruPageController _wideController;
  late final YaruPageController _narrowController;

  @override
  void initState() {
    super.initState();
    final initial = ref.read(navigationBlocProvider).section;
    _wideController = YaruPageController(
      length: NavShellEntries.all.length,
      initialIndex: NavShellEntries.indexFor(initial),
    );
    _narrowController = YaruPageController(
      length: NavShellEntries.pages.length,
      initialIndex: NavShellEntries.narrowIndexFor(initial),
    );
  }

  @override
  void dispose() {
    _wideController.dispose();
    _narrowController.dispose();
    super.dispose();
  }

  void _navigateTo(AppSection section) {
    final bloc = ref.read(navigationBlocProvider.bloc);
    bloc.add(NavigationSectionSelected(section));
  }

  @override
  Widget build(BuildContext context) {
    // Keep controllers in sync with navigation bloc.
    ref.listen(navigationBlocProvider, (prev, next) {
      if (prev?.section == next.section) return;
      final wideIdx = NavShellEntries.indexFor(next.section);
      if (_wideController.index != wideIdx) {
        _wideController.index = wideIdx;
      }
      final narrowIdx = NavShellEntries.narrowIndexFor(next.section);
      if (_narrowController.index != narrowIdx) {
        _narrowController.index = narrowIdx;
      }
    });

    final width = MediaQuery.of(context).size.width;

    if (width < kYaruMasterDetailBreakpoint) {
      // Narrow layout — icons-only rail, no section headers.
      final style = width > 500
          ? YaruNavigationRailStyle.labelled
          : YaruNavigationRailStyle.compact;

      return Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kYaruTitleBarHeight),
          child: Consumer(
            builder: (context, ref, _) {
              final section = ref.watch(navigationBlocProvider).section;
              return YaruWindowTitleBar(
                title: Text(section.label),
                border: BorderSide.none,
              );
            },
          ),
        ),
        body: YaruNavigationPage(
          controller: _narrowController,
          itemBuilder: (context, index, selected) => YaruNavigationRailItem(
            icon: Icon(NavShellEntries.pages[index].yaruIcon),
            label: Text(NavShellEntries.pages[index].label),
            tooltip: NavShellEntries.pages[index].label,
            style: style,
          ),
          pageBuilder: (context, index) =>
              _buildPage(NavShellEntries.pages[index]),
          onSelected: (index) => _navigateTo(NavShellEntries.pages[index]),
        ),
      );
    }

    // Wide layout — sidebar with section headers.
    return YaruMasterDetailPage(
      controller: _wideController,
      paneLayoutDelegate: const YaruResizablePaneDelegate(
        initialPaneSize: 280,
        minPageSize: kYaruMasterDetailBreakpoint / 2,
        minPaneSize: 175,
      ),
      tileBuilder: (context, index, selected, availableWidth) {
        final entry = NavShellEntries.all[index];
        return switch (entry) {
          NavHeader h => _buildSectionHeader(context, h.title),
          NavPageEntry p => YaruMasterTile(
              leading: Icon(p.section.yaruIcon),
              title: Text(p.section.label),
            ),
        };
      },
      pageBuilder: (context, index) {
        final entry = NavShellEntries.all[index];
        if (entry is! NavPageEntry) {
          // Headers have no detail page — show whatever was previously selected.
          final currentSection = ref.read(navigationBlocProvider).section;
          return YaruDetailPage(
            appBar: YaruWindowTitleBar(
              border: BorderSide.none,
              title: Text(currentSection.label),
            ),
            body: _buildPage(currentSection),
          );
        }
        return YaruDetailPage(
          appBar: YaruWindowTitleBar(
            border: BorderSide.none,
            leading: Navigator.of(context).canPop()
                ? const YaruBackButton()
                : null,
            title: Text(entry.section.label),
          ),
          body: _buildPage(entry.section),
        );
      },
      appBar: YaruWindowTitleBar(
        title: const Text('Lenovo Legion Linux'),
        border: BorderSide.none,
        backgroundColor: YaruMasterDetailTheme.of(context).sideBarColor,
      ),
      onSelected: (index) {
        if (index == null) return;
        final entry = NavShellEntries.all[index];
        if (entry is NavPageEntry) {
          _navigateTo(entry.section);
        }
        // NavHeader taps are ignored.
      },
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _buildPage(AppSection section) {
    // Temporary stubs for new sections — replaced as each task completes.
    switch (section) {
      case AppSection.dashboard:
        return const DashboardPage();
      case AppSection.power:
        return const PowerPage();
      case AppSection.fans:
        return const FansPage();
      case AppSection.battery:
        return const BatteryDevicesPage(); // replaced in Task 14
      case AppSection.devices:
        return const BatteryDevicesPage(); // replaced in Task 15
      case AppSection.dgpu:
        return const DgpuPage();
      case AppSection.display:
        return const DisplayLightingPage(); // replaced in Task 12
      case AppSection.lighting:
        return const DisplayLightingPage(); // replaced in Task 13
      case AppSection.automation:
        return const AutomationPage();
      case AppSection.settings:
        return const SettingsPage();
      case AppSection.diagnostics:
        return const AboutPage(); // replaced in Task 21
    }
  }
}
```

**Step 3: Run the app to verify**

```bash
flutter run -d linux
```

Verify: sidebar shows grouped headers (PERFORMANCE, HARDWARE, DISPLAY, SYSTEM), clicking a header does nothing, clicking a page item navigates correctly.

**Step 4: Run tests**

```bash
flutter test -v
```

Expected: All pass.

**Step 5: Commit**

```bash
git add lib/features/navigation/view/navigation_shell.dart
git commit -m "feat(nav): add grouped sidebar with section headers via NavEntry"
```

---

### Task 4: Create AppControlCard and DashboardCard widgets

**Files:**
- Modify: `lib/core/widgets/app_shell_components.dart`
- Create: `test/core/widgets/app_control_card_test.dart`

**Context:** `AppControlCard` replaces `AppSectionCard` on feature pages. It adds a required `icon` and optional `tint`. `DashboardCard` is the dashboard-only variant with the same API. `AppSectionCard` is kept unchanged (still used in Diagnostics and Automation).

**Step 1: Write the failing tests**

```dart
// test/core/widgets/app_control_card_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/widgets/app_shell_components.dart';
import 'package:yaru/yaru.dart';

void main() {
  testWidgets('AppControlCard renders icon and title', (tester) async {
    await tester.pumpWidget(
      YaruTheme(
        builder: (context, yaru, _) => MaterialApp(
          theme: yaru.theme,
          home: Scaffold(
            body: AppControlCard(
              icon: Icons.bolt,
              title: 'Power',
              children: const [Text('content')],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byIcon(Icons.bolt), findsOneWidget);
    expect(find.text('Power'), findsOneWidget);
    expect(find.text('content'), findsOneWidget);
  });

  testWidgets('AppControlCard renders description when provided', (tester) async {
    await tester.pumpWidget(
      YaruTheme(
        builder: (context, yaru, _) => MaterialApp(
          theme: yaru.theme,
          home: Scaffold(
            body: AppControlCard(
              icon: Icons.bolt,
              title: 'Power',
              description: 'Manage performance',
              children: const [],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Manage performance'), findsOneWidget);
  });

  testWidgets('DashboardCard renders icon and title', (tester) async {
    await tester.pumpWidget(
      YaruTheme(
        builder: (context, yaru, _) => MaterialApp(
          theme: yaru.theme,
          home: Scaffold(
            body: DashboardCard(
              icon: Icons.thermostat,
              title: 'Temperature',
              children: const [Text('61°C')],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byIcon(Icons.thermostat), findsOneWidget);
    expect(find.text('Temperature'), findsOneWidget);
    expect(find.text('61°C'), findsOneWidget);
  });
}
```

**Step 2: Run test to verify it fails**

```bash
flutter test test/core/widgets/app_control_card_test.dart -v
```

Expected: compile error — `AppControlCard`, `DashboardCard` not found.

**Step 3: Add widgets to `lib/core/widgets/app_shell_components.dart`**

Append after the existing `AppSwitchTile` class:

```dart
/// A feature-page section card with a leading icon and optional background tint.
/// Use instead of [AppSectionCard] for interactive control sections.
class AppControlCard extends StatelessWidget {
  const AppControlCard({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.trailing,
    this.tint,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String? description;
  final Widget? trailing;
  final Color? tint;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    Widget section = YaruSection(
      headline: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Icon(icon, size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: textTheme.titleMedium)),
            if (trailing != null) trailing!,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (description != null) ...[
            Text(description!, style: textTheme.bodySmall),
            const SizedBox(height: 8),
          ],
          ...children,
        ],
      ),
    );

    if (tint != null) {
      section = ColoredBox(
        color: tint!.withValues(alpha: 0.06),
        child: section,
      );
    }

    return section;
  }
}

/// A dashboard-specific card with an icon, optional background tint,
/// and slightly more visual weight than [AppControlCard].
class DashboardCard extends StatelessWidget {
  const DashboardCard({
    super.key,
    required this.icon,
    required this.title,
    this.trailing,
    this.tint,
    required this.children,
  });

  final IconData icon;
  final String title;
  final Widget? trailing;
  final Color? tint;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: tint != null
          ? Color.alphaBlend(tint!.withValues(alpha: 0.08), scheme.surface)
          : scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title, style: textTheme.titleMedium),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}
```

**Step 4: Run tests**

```bash
flutter test test/core/widgets/app_control_card_test.dart -v
flutter test -v
```

Expected: All pass.

**Step 5: Commit**

```bash
git add lib/core/widgets/app_shell_components.dart \
        test/core/widgets/app_control_card_test.dart
git commit -m "feat(widgets): add AppControlCard and DashboardCard with icon and tint support"
```

---

## Phase 2 — Sensor Infrastructure

### Task 5: Extend LegionSysfsService with new sensor reads

**Files:**
- Modify: `lib/core/services/legion_sysfs_service.dart`
- Modify: `test/core/services/legion_sysfs_service_test.dart` (create if not exists)

**Context:** Add reads for: CPU utilisation (from `/proc/stat`), average CPU clock (from `/sys/devices/system/cpu/cpufreq/`), battery detail fields (cycle count, full capacity, design capacity, temperature, current/voltage for power draw), disk temperature (via hwmon), motherboard temperature (via hwmon), device identity (DMI sysfs), CPU name (from `/proc/cpuinfo`).

GPU stats (utilisation, VRAM, clock, power draw) come from `nvidia-smi` and are added in Task 6 as a separate `NvidiaSmiService`.

**Step 1: Write tests for the new sysfs reads**

```dart
// test/core/services/legion_sysfs_service_extended_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/services/legion_sysfs_service.dart';

void main() {
  // These are integration-style tests that return null on CI (no hardware).
  // They verify the methods exist and return null gracefully, not actual values.
  final service = LegionSysfsService();

  group('LegionSysfsService extended reads', () {
    test('readCpuUtilisationPercent returns double? without throwing', () async {
      final result = await service.readCpuUtilisationPercent();
      expect(result, anyOf(isNull, isA<double>()));
    });

    test('readAverageCpuClockGhz returns double? without throwing', () async {
      final result = await service.readAverageCpuClockGhz();
      expect(result, anyOf(isNull, isA<double>()));
    });

    test('readBatteryCycleCount returns int? without throwing', () async {
      final result = await service.readBatteryCycleCount();
      expect(result, anyOf(isNull, isA<int>()));
    });

    test('readBatteryFullCapacityWh returns double? without throwing', () async {
      final result = await service.readBatteryFullCapacityWh();
      expect(result, anyOf(isNull, isA<double>()));
    });

    test('readBatteryDesignCapacityWh returns double? without throwing', () async {
      final result = await service.readBatteryDesignCapacityWh();
      expect(result, anyOf(isNull, isA<double>()));
    });

    test('readBatteryCurrentCapacityWh returns double? without throwing', () async {
      final result = await service.readBatteryCurrentCapacityWh();
      expect(result, anyOf(isNull, isA<double>()));
    });

    test('readBatteryPowerDrawW returns double? without throwing', () async {
      final result = await service.readBatteryPowerDrawW();
      expect(result, anyOf(isNull, isA<double>()));
    });

    test('readBatteryTempC returns double? without throwing', () async {
      final result = await service.readBatteryTempC();
      expect(result, anyOf(isNull, isA<double>()));
    });

    test('readMotherboardTempC returns double? without throwing', () async {
      final result = await service.readMotherboardTempC();
      expect(result, anyOf(isNull, isA<double>()));
    });

    test('readDiskTempC returns double? without throwing', () async {
      final result = await service.readDiskTempC();
      expect(result, anyOf(isNull, isA<double>()));
    });

    test('readDeviceProductFamily returns String? without throwing', () async {
      final result = await service.readDeviceProductFamily();
      expect(result, anyOf(isNull, isA<String>()));
    });

    test('readDeviceProductName returns String? without throwing', () async {
      final result = await service.readDeviceProductName();
      expect(result, anyOf(isNull, isA<String>()));
    });

    test('readDeviceSerial returns String? without throwing', () async {
      final result = await service.readDeviceSerial();
      expect(result, anyOf(isNull, isA<String>()));
    });

    test('readBiosVersion returns String? without throwing', () async {
      final result = await service.readBiosVersion();
      expect(result, anyOf(isNull, isA<String>()));
    });

    test('readCpuName returns String? without throwing', () async {
      final result = await service.readCpuName();
      expect(result, anyOf(isNull, isA<String>()));
    });
  });
}
```

**Step 2: Run to confirm the test fails**

```bash
flutter test test/core/services/legion_sysfs_service_extended_test.dart -v
```

Expected: compile errors — new methods not yet on `LegionSysfsService`.

**Step 3: Add methods to `lib/core/services/legion_sysfs_service.dart`**

Add these constants at the top of the class, after existing ones:

```dart
  static const String _batteryPath = '/sys/class/power_supply/BAT0';
  static const String _dmiPath = '/sys/class/dmi/id';
```

Add these methods (append before the private helpers):

```dart
  /// CPU utilisation percentage (0–100). Computed from /proc/stat deltas.
  /// Returns null if /proc/stat is not readable.
  Future<double?> readCpuUtilisationPercent() async {
    try {
      final line1 = await _readFirstCpuStatLine();
      if (line1 == null) return null;
      await Future.delayed(const Duration(milliseconds: 200));
      final line2 = await _readFirstCpuStatLine();
      if (line2 == null) return null;

      final fields1 = line1.split(RegExp(r'\s+')).skip(1).map(int.parse).toList();
      final fields2 = line2.split(RegExp(r'\s+')).skip(1).map(int.parse).toList();

      final idle1 = fields1.length > 3 ? fields1[3] : 0;
      final idle2 = fields2.length > 3 ? fields2[3] : 0;
      final total1 = fields1.fold(0, (a, b) => a + b);
      final total2 = fields2.fold(0, (a, b) => a + b);

      final totalDelta = total2 - total1;
      final idleDelta = idle2 - idle1;
      if (totalDelta <= 0) return null;

      return (1.0 - idleDelta / totalDelta) * 100.0;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _readFirstCpuStatLine() async {
    try {
      final file = File('/proc/stat');
      if (!await file.exists()) return null;
      final lines = await file.readAsLines();
      return lines.firstWhere(
        (l) => l.startsWith('cpu '),
        orElse: () => '',
      );
    } catch (_) {
      return null;
    }
  }

  /// Average clock speed across all online CPUs in GHz.
  Future<double?> readAverageCpuClockGhz() async {
    try {
      final cpuDir = Directory('/sys/devices/system/cpu');
      if (!await cpuDir.exists()) return null;

      final clocks = <int>[];
      await for (final entity in cpuDir.list()) {
        if (entity is! Directory) continue;
        final name = entity.path.split('/').last;
        if (!RegExp(r'^cpu\d+$').hasMatch(name)) continue;
        final freqPath = '${entity.path}/cpufreq/scaling_cur_freq';
        final val = await readIntFile(freqPath);
        if (val != null && val > 0) clocks.add(val);
      }
      if (clocks.isEmpty) return null;
      final avgKhz = clocks.fold(0, (a, b) => a + b) / clocks.length;
      return avgKhz / 1e6; // kHz → GHz
    } catch (_) {
      return null;
    }
  }

  /// Battery cycle count from /sys/class/power_supply/BAT0/cycle_count.
  Future<int?> readBatteryCycleCount() async {
    return readIntFile('$_batteryPath/cycle_count');
  }

  /// Battery full charge capacity in Wh.
  Future<double?> readBatteryFullCapacityWh() async {
    // energy_full is in μWh on most systems; charge_full in μAh if voltage known.
    final energyFull = await readIntFile('$_batteryPath/energy_full');
    if (energyFull != null) return energyFull / 1e6;
    // fallback: charge_full * voltage_now
    final chargeFull = await readIntFile('$_batteryPath/charge_full');
    final voltageNow = await readIntFile('$_batteryPath/voltage_now');
    if (chargeFull != null && voltageNow != null) {
      return (chargeFull / 1e6) * (voltageNow / 1e6);
    }
    return null;
  }

  /// Battery design capacity in Wh.
  Future<double?> readBatteryDesignCapacityWh() async {
    final energyDesign = await readIntFile('$_batteryPath/energy_full_design');
    if (energyDesign != null) return energyDesign / 1e6;
    final chargeDesign = await readIntFile('$_batteryPath/charge_full_design');
    final voltageNow = await readIntFile('$_batteryPath/voltage_now');
    if (chargeDesign != null && voltageNow != null) {
      return (chargeDesign / 1e6) * (voltageNow / 1e6);
    }
    return null;
  }

  /// Battery current capacity in Wh.
  Future<double?> readBatteryCurrentCapacityWh() async {
    final energyNow = await readIntFile('$_batteryPath/energy_now');
    if (energyNow != null) return energyNow / 1e6;
    final chargeNow = await readIntFile('$_batteryPath/charge_now');
    final voltageNow = await readIntFile('$_batteryPath/voltage_now');
    if (chargeNow != null && voltageNow != null) {
      return (chargeNow / 1e6) * (voltageNow / 1e6);
    }
    return null;
  }

  /// Battery power draw in watts (positive = discharging, negative = charging).
  Future<double?> readBatteryPowerDrawW() async {
    final powerNow = await readIntFile('$_batteryPath/power_now');
    if (powerNow != null) {
      final status = await _readTrimmedFile('$_batteryPath/status');
      final sign = status == 'Charging' ? -1.0 : 1.0;
      return sign * powerNow / 1e6;
    }
    final currentNow = await readIntFile('$_batteryPath/current_now');
    final voltageNow = await readIntFile('$_batteryPath/voltage_now');
    if (currentNow != null && voltageNow != null) {
      final status = await _readTrimmedFile('$_batteryPath/status');
      final sign = status == 'Charging' ? -1.0 : 1.0;
      return sign * (currentNow / 1e6) * (voltageNow / 1e6);
    }
    return null;
  }

  /// Battery temperature in °C (from hwmon or power_supply).
  Future<double?> readBatteryTempC() async {
    final raw = await readIntFile('$_batteryPath/temp');
    if (raw != null) return raw / 10.0; // tenths of °C
    return null;
  }

  /// Motherboard temperature in °C via hwmon (e.g. acpitz, it87, nct6775).
  Future<double?> readMotherboardTempC() async {
    final path = await _findHwmonTempInput(
      driverNames: {'acpitz', 'it87', 'nct6775', 'nct6776', 'nct6779'},
      fallbackIndex: 1,
    );
    final raw = path == null ? null : await readIntFile(path);
    return raw == null ? null : milliDegreesToC(raw);
  }

  /// Primary disk temperature in °C via hwmon (NVMe or SATA).
  Future<double?> readDiskTempC() async {
    final path = await _findHwmonTempInput(
      driverNames: {'nvme', 'drivetemp'},
      fallbackIndex: 1,
    );
    final raw = path == null ? null : await readIntFile(path);
    return raw == null ? null : milliDegreesToC(raw);
  }

  // ── Device identity (DMI) ──────────────────────────────────────────────────

  Future<String?> readDeviceProductFamily() async =>
      _readTrimmedFile('$_dmiPath/product_family');

  Future<String?> readDeviceProductName() async =>
      _readTrimmedFile('$_dmiPath/product_name');

  Future<String?> readDeviceSerial() async =>
      _readTrimmedFile('$_dmiPath/product_serial');

  Future<String?> readBiosVersion() async =>
      _readTrimmedFile('$_dmiPath/bios_version');

  /// CPU model name from /proc/cpuinfo.
  Future<String?> readCpuName() async {
    try {
      final file = File('/proc/cpuinfo');
      if (!await file.exists()) return null;
      await for (final line in file.openRead().transform(
            const LineSplitter(),
          )) {
        if (line.startsWith('model name')) {
          final parts = line.split(':');
          if (parts.length >= 2) return parts.sublist(1).join(':').trim();
        }
      }
    } catch (_) {}
    return null;
  }
```

Also add `dart:convert` import for `LineSplitter`:

At the top of `legion_sysfs_service.dart`, add:
```dart
import 'dart:convert';
```

**Step 4: Run tests**

```bash
flutter test test/core/services/legion_sysfs_service_extended_test.dart -v
flutter test -v
```

Expected: All pass (methods exist and return null gracefully without hardware).

**Step 5: Commit**

```bash
git add lib/core/services/legion_sysfs_service.dart \
        test/core/services/legion_sysfs_service_extended_test.dart
git commit -m "feat(sysfs): add sensor reads for CPU util/clock, battery detail, temps, DMI identity"
```

---

### Task 6: Create NvidiaSmiService, LiveSensorSnapshot, LiveSensorRepository, LiveSensorBloc

**Files:**
- Create: `lib/core/services/nvidia_smi_service.dart`
- Create: `lib/features/sensors/models/live_sensor_snapshot.dart`
- Create: `lib/features/sensors/repository/live_sensor_repository.dart`
- Create: `lib/features/sensors/bloc/live_sensor_bloc.dart`
- Create: `lib/features/sensors/bloc/live_sensor_event.dart`
- Create: `lib/features/sensors/bloc/live_sensor_state.dart`
- Create: `lib/features/sensors/providers/live_sensor_provider.dart`
- Create: `test/features/sensors/live_sensor_snapshot_test.dart`
- Create: `test/features/sensors/live_sensor_bloc_test.dart`

**Context:** `LiveSensorSnapshot` holds all live sensor fields as nullable. `NvidiaSmiService` calls `nvidia-smi` and parses GPU stats. `LiveSensorRepository.loadSnapshot()` reads everything in parallel. `LiveSensorBloc` polls every 2 s and exposes the latest snapshot. Both the Dashboard and the new Diagnostics page will watch `liveSensorBlocProvider`.

**Step 1: Write the failing tests**

```dart
// test/features/sensors/live_sensor_snapshot_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/sensors/models/live_sensor_snapshot.dart';

void main() {
  group('LiveSensorSnapshot', () {
    test('initial has all nulls', () {
      final s = LiveSensorSnapshot.initial();
      expect(s.cpuName, isNull);
      expect(s.cpuTempC, isNull);
      expect(s.fan1Rpm, isNull);
      expect(s.batteryPercent, isNull);
    });

    test('equality holds when all fields match', () {
      final a = LiveSensorSnapshot(
        cpuName: 'Ryzen 7',
        cpuTempC: 61.0,
        cpuUtilPercent: 12.0,
        cpuClockGhz: 3.1,
        fan1Rpm: 1800,
        fan2Rpm: 1500,
        gpuName: null,
        gpuTempC: null,
        gpuUtilPercent: null,
        gpuClockGhz: null,
        gpuVramUsedGb: null,
        gpuVramTotalGb: null,
        gpuFanRpm: null,
        gpuPowerDrawW: null,
        gpuIsDiscrete: false,
        motherboardTempC: null,
        batteryPercent: 78,
        batteryCharging: true,
        batteryPowerDrawW: -18.0,
        diskTempC: null,
      );
      final b = a;
      expect(a, equals(b));
    });

    test('gpuIsDiscrete defaults to false', () {
      expect(LiveSensorSnapshot.initial().gpuIsDiscrete, isFalse);
    });
  });
}
```

```dart
// test/features/sensors/live_sensor_bloc_test.dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:legion_frontend/features/sensors/bloc/live_sensor_bloc.dart';
import 'package:legion_frontend/features/sensors/bloc/live_sensor_event.dart';
import 'package:legion_frontend/features/sensors/bloc/live_sensor_state.dart';
import 'package:legion_frontend/features/sensors/models/live_sensor_snapshot.dart';
import 'package:legion_frontend/features/sensors/repository/live_sensor_repository.dart';

class MockLiveSensorRepository extends Mock implements LiveSensorRepository {}

void main() {
  late MockLiveSensorRepository repository;

  setUp(() {
    repository = MockLiveSensorRepository();
  });

  group('LiveSensorBloc', () {
    final snapshot = LiveSensorSnapshot(
      cpuName: 'Ryzen 7',
      cpuTempC: 61.0,
      cpuUtilPercent: 12.0,
      cpuClockGhz: 3.1,
      fan1Rpm: 1800,
      fan2Rpm: 1500,
      gpuName: null,
      gpuTempC: null,
      gpuUtilPercent: null,
      gpuClockGhz: null,
      gpuVramUsedGb: null,
      gpuVramTotalGb: null,
      gpuFanRpm: null,
      gpuPowerDrawW: null,
      gpuIsDiscrete: false,
      motherboardTempC: null,
      batteryPercent: 78,
      batteryCharging: true,
      batteryPowerDrawW: -18.0,
      diskTempC: null,
    );

    test('initial state has initial snapshot', () {
      final bloc = LiveSensorBloc(
        repository: repository,
        pollInterval: const Duration(seconds: 60),
      );
      expect(bloc.state.snapshot, LiveSensorSnapshot.initial());
      bloc.close();
    });

    blocTest<LiveSensorBloc, LiveSensorState>(
      'emits loaded snapshot on LiveSensorStarted',
      build: () {
        when(() => repository.loadSnapshot())
            .thenAnswer((_) async => snapshot);
        return LiveSensorBloc(
          repository: repository,
          pollInterval: const Duration(seconds: 60),
        );
      },
      act: (bloc) => bloc.add(const LiveSensorStarted()),
      wait: const Duration(milliseconds: 100),
      expect: () => [
        LiveSensorState(snapshot: snapshot, isLoading: false),
      ],
    );

    blocTest<LiveSensorBloc, LiveSensorState>(
      'emits error state when loadSnapshot throws',
      build: () {
        when(() => repository.loadSnapshot())
            .thenThrow(Exception('sysfs error'));
        return LiveSensorBloc(
          repository: repository,
          pollInterval: const Duration(seconds: 60),
        );
      },
      act: (bloc) => bloc.add(const LiveSensorStarted()),
      wait: const Duration(milliseconds: 100),
      expect: () => [
        isA<LiveSensorState>().having((s) => s.errorMessage, 'error', isNotNull),
      ],
    );
  });
}
```

**Step 2: Run tests to verify they fail**

```bash
flutter test test/features/sensors/ -v
```

**Step 3: Create all sensor files**

`lib/core/services/nvidia_smi_service.dart`:
```dart
import 'dart:io';

class NvidiaSmiSnapshot {
  const NvidiaSmiSnapshot({
    required this.name,
    required this.utilPercent,
    required this.clkGhz,
    required this.tempC,
    required this.fanRpm,
    required this.vramUsedGb,
    required this.vramTotalGb,
    required this.powerDrawW,
  });

  final String? name;
  final double? utilPercent;
  final double? clkGhz;
  final double? tempC;
  final int? fanRpm;
  final double? vramUsedGb;
  final double? vramTotalGb;
  final double? powerDrawW;
}

class NvidiaSmiService {
  /// Returns null if nvidia-smi is not available or dGPU is not active.
  Future<NvidiaSmiSnapshot?> readSnapshot() async {
    try {
      final result = await Process.run('nvidia-smi', [
        '--query-gpu=name,utilization.gpu,clocks.gr,temperature.gpu,'
            'fan.speed,memory.used,memory.total,power.draw',
        '--format=csv,noheader,nounits',
      ]);
      if (result.exitCode != 0) return null;
      final line = (result.stdout as String).trim();
      if (line.isEmpty) return null;
      final parts = line.split(',').map((s) => s.trim()).toList();
      if (parts.length < 8) return null;

      double? parseDouble(String s) => double.tryParse(s.replaceAll('[Not Supported]', '').trim());
      int? parseInt(String s) => int.tryParse(s.replaceAll('[Not Supported]', '').trim());

      return NvidiaSmiSnapshot(
        name: parts[0].isEmpty ? null : parts[0],
        utilPercent: parseDouble(parts[1]),
        clkGhz: parseDouble(parts[2]) != null ? parseDouble(parts[2])! / 1000.0 : null,
        tempC: parseDouble(parts[3]),
        fanRpm: parseInt(parts[4]),
        vramUsedGb: parseDouble(parts[5]) != null ? parseDouble(parts[5])! / 1024.0 : null,
        vramTotalGb: parseDouble(parts[6]) != null ? parseDouble(parts[6])! / 1024.0 : null,
        powerDrawW: parseDouble(parts[7]),
      );
    } catch (_) {
      return null;
    }
  }
}
```

`lib/features/sensors/models/live_sensor_snapshot.dart`:
```dart
import 'package:equatable/equatable.dart';

class LiveSensorSnapshot extends Equatable {
  const LiveSensorSnapshot({
    required this.cpuName,
    required this.cpuTempC,
    required this.cpuUtilPercent,
    required this.cpuClockGhz,
    required this.fan1Rpm,
    required this.fan2Rpm,
    required this.gpuName,
    required this.gpuTempC,
    required this.gpuUtilPercent,
    required this.gpuClockGhz,
    required this.gpuVramUsedGb,
    required this.gpuVramTotalGb,
    required this.gpuFanRpm,
    required this.gpuPowerDrawW,
    required this.gpuIsDiscrete,
    required this.motherboardTempC,
    required this.batteryPercent,
    required this.batteryCharging,
    required this.batteryPowerDrawW,
    required this.diskTempC,
  });

  factory LiveSensorSnapshot.initial() => const LiveSensorSnapshot(
    cpuName: null,
    cpuTempC: null,
    cpuUtilPercent: null,
    cpuClockGhz: null,
    fan1Rpm: null,
    fan2Rpm: null,
    gpuName: null,
    gpuTempC: null,
    gpuUtilPercent: null,
    gpuClockGhz: null,
    gpuVramUsedGb: null,
    gpuVramTotalGb: null,
    gpuFanRpm: null,
    gpuPowerDrawW: null,
    gpuIsDiscrete: false,
    motherboardTempC: null,
    batteryPercent: null,
    batteryCharging: null,
    batteryPowerDrawW: null,
    diskTempC: null,
  );

  final String? cpuName;
  final double? cpuTempC;
  final double? cpuUtilPercent;
  final double? cpuClockGhz;
  final int? fan1Rpm;
  final int? fan2Rpm;

  // Active GPU (dGPU when active, iGPU otherwise).
  final String? gpuName;
  final double? gpuTempC;
  final double? gpuUtilPercent;
  final double? gpuClockGhz;
  final double? gpuVramUsedGb;
  final double? gpuVramTotalGb;
  final int? gpuFanRpm;
  final double? gpuPowerDrawW;
  final bool gpuIsDiscrete;

  final double? motherboardTempC;
  final int? batteryPercent;
  final bool? batteryCharging;
  final double? batteryPowerDrawW;
  final double? diskTempC;

  @override
  List<Object?> get props => [
    cpuName, cpuTempC, cpuUtilPercent, cpuClockGhz,
    fan1Rpm, fan2Rpm,
    gpuName, gpuTempC, gpuUtilPercent, gpuClockGhz,
    gpuVramUsedGb, gpuVramTotalGb, gpuFanRpm, gpuPowerDrawW, gpuIsDiscrete,
    motherboardTempC,
    batteryPercent, batteryCharging, batteryPowerDrawW,
    diskTempC,
  ];
}
```

`lib/features/sensors/repository/live_sensor_repository.dart`:
```dart
import '../../../core/services/legion_sysfs_service.dart';
import '../../../core/services/nvidia_smi_service.dart';
import '../models/live_sensor_snapshot.dart';

class LiveSensorRepository {
  const LiveSensorRepository({
    required LegionSysfsService sysfsService,
    required NvidiaSmiService nvidiaSmiService,
  }) : _sysfs = sysfsService,
       _nvidia = nvidiaSmiService;

  final LegionSysfsService _sysfs;
  final NvidiaSmiService _nvidia;

  Future<LiveSensorSnapshot> loadSnapshot() async {
    final results = await Future.wait([
      _sysfs.readCpuName(),
      _sysfs.readCpuTempC(),
      _sysfs.readCpuUtilisationPercent(),
      _sysfs.readAverageCpuClockGhz(),
      _sysfs.readFan1Rpm(),
      _sysfs.readFan2Rpm(),
      _sysfs.readMotherboardTempC(),
      _sysfs.readOnPowerSupplyMode(),
      _sysfs.readBatteryPowerDrawW(),
      _sysfs.readDiskTempC(),
      _nvidia.readSnapshot(),
    ]);

    final cpuName = results[0] as String?;
    final cpuTempC = results[1] as double?;
    final cpuUtil = results[2] as double?;
    final cpuClock = results[3] as double?;
    final fan1 = results[4] as int?;
    final fan2 = results[5] as int?;
    final moboTemp = results[6] as double?;
    final onPowerSupply = results[7] as bool?;
    final batteryDraw = results[8] as double?;
    final diskTemp = results[9] as double?;
    final nvidia = results[10] as NvidiaSmiSnapshot?;

    // Battery percent from sysfs.
    final batteryPercent = await _sysfs.readIntFile(
      '/sys/class/power_supply/BAT0/capacity',
    );
    final batteryStatus = await _sysfs.readIntFile(
          '/sys/class/power_supply/BAT0/status',
        ) == null
        ? null
        : null; // status is a string, read separately
    // Read charging state directly.
    final batteryStatusStr = await _readBatteryStatus();

    if (nvidia != null) {
      // dGPU is active.
      return LiveSensorSnapshot(
        cpuName: cpuName,
        cpuTempC: cpuTempC,
        cpuUtilPercent: cpuUtil,
        cpuClockGhz: cpuClock,
        fan1Rpm: fan1,
        fan2Rpm: fan2,
        gpuName: nvidia.name,
        gpuTempC: nvidia.tempC,
        gpuUtilPercent: nvidia.utilPercent,
        gpuClockGhz: nvidia.clkGhz,
        gpuVramUsedGb: nvidia.vramUsedGb,
        gpuVramTotalGb: nvidia.vramTotalGb,
        gpuFanRpm: nvidia.fanRpm,
        gpuPowerDrawW: nvidia.powerDrawW,
        gpuIsDiscrete: true,
        motherboardTempC: moboTemp,
        batteryPercent: batteryPercent,
        batteryCharging: batteryStatusStr == 'Charging',
        batteryPowerDrawW: batteryDraw,
        diskTempC: diskTemp,
      );
    }

    // iGPU fallback — use existing sysfs GPU temp.
    final igpuTemp = await _sysfs.readGpuTempC();
    return LiveSensorSnapshot(
      cpuName: cpuName,
      cpuTempC: cpuTempC,
      cpuUtilPercent: cpuUtil,
      cpuClockGhz: cpuClock,
      fan1Rpm: fan1,
      fan2Rpm: fan2,
      gpuName: null,
      gpuTempC: igpuTemp,
      gpuUtilPercent: null,
      gpuClockGhz: null,
      gpuVramUsedGb: null,
      gpuVramTotalGb: null,
      gpuFanRpm: null,
      gpuPowerDrawW: null,
      gpuIsDiscrete: false,
      motherboardTempC: moboTemp,
      batteryPercent: batteryPercent,
      batteryCharging: batteryStatusStr == 'Charging',
      batteryPowerDrawW: batteryDraw,
      diskTempC: diskTemp,
    );
  }

  Future<String?> _readBatteryStatus() async {
    try {
      final file = File('/sys/class/power_supply/BAT0/status');
      if (!await file.exists()) return null;
      return (await file.readAsString()).trim();
    } catch (_) {
      return null;
    }
  }
}
```

Add `import 'dart:io';` at the top of `live_sensor_repository.dart`.

`lib/features/sensors/bloc/live_sensor_event.dart`:
```dart
import 'package:equatable/equatable.dart';

sealed class LiveSensorEvent extends Equatable {
  const LiveSensorEvent();
  @override
  List<Object?> get props => const [];
}

final class LiveSensorStarted extends LiveSensorEvent {
  const LiveSensorStarted();
}

final class LiveSensorTicked extends LiveSensorEvent {
  const LiveSensorTicked();
}
```

`lib/features/sensors/bloc/live_sensor_state.dart`:
```dart
import 'package:equatable/equatable.dart';
import '../models/live_sensor_snapshot.dart';

class LiveSensorState extends Equatable {
  const LiveSensorState({
    required this.snapshot,
    this.isLoading = false,
    this.errorMessage,
  });

  factory LiveSensorState.initial() => LiveSensorState(
    snapshot: LiveSensorSnapshot.initial(),
    isLoading: false,
  );

  final LiveSensorSnapshot snapshot;
  final bool isLoading;
  final String? errorMessage;

  LiveSensorState copyWith({
    LiveSensorSnapshot? snapshot,
    bool? isLoading,
    String? errorMessage,
  }) {
    return LiveSensorState(
      snapshot: snapshot ?? this.snapshot,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [snapshot, isLoading, errorMessage];
}
```

`lib/features/sensors/bloc/live_sensor_bloc.dart`:
```dart
import 'dart:async';
import 'package:riverbloc/riverbloc.dart';
import '../repository/live_sensor_repository.dart';
import 'live_sensor_event.dart';
import 'live_sensor_state.dart';

class LiveSensorBloc extends Bloc<LiveSensorEvent, LiveSensorState> {
  LiveSensorBloc({
    required LiveSensorRepository repository,
    Duration pollInterval = const Duration(seconds: 2),
  }) : _repository = repository,
       _pollInterval = pollInterval,
       super(LiveSensorState.initial()) {
    on<LiveSensorStarted>(_onStarted);
    on<LiveSensorTicked>(_onTicked);
  }

  final LiveSensorRepository _repository;
  final Duration _pollInterval;

  Timer? _pollTimer;
  bool _started = false;
  bool _refreshInFlight = false;

  Future<void> _onStarted(LiveSensorStarted event, Emitter<LiveSensorState> emit) async {
    if (_started) return;
    _started = true;
    await _reload(emit);
    _pollTimer = Timer.periodic(_pollInterval, (_) => add(const LiveSensorTicked()));
  }

  Future<void> _onTicked(LiveSensorTicked event, Emitter<LiveSensorState> emit) async {
    await _reload(emit);
  }

  Future<void> _reload(Emitter<LiveSensorState> emit) async {
    if (_refreshInFlight) return;
    _refreshInFlight = true;
    try {
      final snapshot = await _repository.loadSnapshot();
      emit(state.copyWith(snapshot: snapshot, isLoading: false, errorMessage: null));
    } catch (error) {
      emit(state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to read sensors: $error',
      ));
    } finally {
      _refreshInFlight = false;
    }
  }

  @override
  Future<void> close() {
    _pollTimer?.cancel();
    return super.close();
  }
}
```

`lib/features/sensors/providers/live_sensor_provider.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverbloc/riverbloc.dart';
import '../../../core/providers/system_services_provider.dart';
import '../../../core/services/nvidia_smi_service.dart';
import '../bloc/live_sensor_bloc.dart';
import '../bloc/live_sensor_state.dart';
import '../repository/live_sensor_repository.dart';

final _liveSensorRepositoryProvider = Provider<LiveSensorRepository>((ref) {
  return LiveSensorRepository(
    sysfsService: ref.watch(sysfsServiceProvider),
    nvidiaSmiService: NvidiaSmiService(),
  );
});

final liveSensorBlocProvider =
    BlocProvider.autoDispose<LiveSensorBloc, LiveSensorState>((ref) {
  return LiveSensorBloc(repository: ref.watch(_liveSensorRepositoryProvider));
});
```

Check `lib/core/providers/system_services_provider.dart` for the `sysfsServiceProvider` name and adjust the import if needed.

**Step 4: Run tests**

```bash
flutter test test/features/sensors/ -v
flutter test -v
```

Expected: All pass.

**Step 5: Commit**

```bash
git add lib/core/services/nvidia_smi_service.dart \
        lib/features/sensors/ \
        test/features/sensors/
git commit -m "feat(sensors): add LiveSensorBloc polling CPU/GPU/battery/temp at 2s"
```

---

## Phase 3 — Dashboard

### Task 7: DeviceIdentitySnapshot + device header widget

**Files:**
- Create: `lib/features/dashboard/models/device_identity_snapshot.dart`
- Create: `lib/features/dashboard/widgets/device_identity_card.dart`
- Modify: `lib/features/dashboard/repository/dashboard_repository.dart`
- Modify: `lib/features/dashboard/models/dashboard_snapshot.dart`
- Create: `test/features/dashboard/device_identity_snapshot_test.dart`

**Step 1: Write the failing test**

```dart
// test/features/dashboard/device_identity_snapshot_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/dashboard/models/device_identity_snapshot.dart';

void main() {
  group('DeviceIdentitySnapshot', () {
    test('displayName returns family when both available', () {
      const s = DeviceIdentitySnapshot(
        productFamily: 'Legion Slim 7',
        productName: '16APH8',
        serial: 'PF3ABC12',
        biosVersion: 'LPCN41WW',
      );
      expect(s.displayName, 'Legion Slim 7 16APH8');
    });

    test('displayName returns family alone when no product name', () {
      const s = DeviceIdentitySnapshot(
        productFamily: 'Legion Slim 7',
        productName: null,
        serial: null,
        biosVersion: null,
      );
      expect(s.displayName, 'Legion Slim 7');
    });

    test('displayName returns Unknown when both null', () {
      const s = DeviceIdentitySnapshot(
        productFamily: null,
        productName: null,
        serial: null,
        biosVersion: null,
      );
      expect(s.displayName, 'Unknown Device');
    });

    test('equality', () {
      const a = DeviceIdentitySnapshot(
        productFamily: 'Legion',
        productName: 'Slim 7',
        serial: 'ABC',
        biosVersion: '1.0',
      );
      const b = DeviceIdentitySnapshot(
        productFamily: 'Legion',
        productName: 'Slim 7',
        serial: 'ABC',
        biosVersion: '1.0',
      );
      expect(a, equals(b));
    });
  });
}
```

**Step 2: Run to verify fails**

```bash
flutter test test/features/dashboard/device_identity_snapshot_test.dart -v
```

**Step 3: Create `lib/features/dashboard/models/device_identity_snapshot.dart`**

```dart
import 'package:equatable/equatable.dart';

class DeviceIdentitySnapshot extends Equatable {
  const DeviceIdentitySnapshot({
    required this.productFamily,
    required this.productName,
    required this.serial,
    required this.biosVersion,
  });

  factory DeviceIdentitySnapshot.initial() => const DeviceIdentitySnapshot(
    productFamily: null,
    productName: null,
    serial: null,
    biosVersion: null,
  );

  final String? productFamily;
  final String? productName;
  final String? serial;
  final String? biosVersion;

  String get displayName {
    final family = productFamily?.trim();
    final name = productName?.trim();
    if (family == null && name == null) return 'Unknown Device';
    if (family == null) return name!;
    if (name == null) return family;
    return '$family $name';
  }

  @override
  List<Object?> get props => [productFamily, productName, serial, biosVersion];
}
```

**Step 4: Add `deviceIdentity` to `DashboardSnapshot`**

In `lib/features/dashboard/models/dashboard_snapshot.dart`, add:
- Field: `final DeviceIdentitySnapshot deviceIdentity;`
- Update `initial()`, `copyWith()`, `props`

**Step 5: Load identity in `DashboardRepository.loadSnapshot()`**

In `dashboard_repository.dart`, read all four DMI fields in parallel as part of `loadSnapshot()`:

```dart
final identity = await _loadDeviceIdentity();
// ... existing reads ...
return DashboardSnapshot(
  // ... existing fields ...
  deviceIdentity: identity,
);
```

```dart
Future<DeviceIdentitySnapshot> _loadDeviceIdentity() async {
  final results = await Future.wait([
    _sysfsService.readDeviceProductFamily(),
    _sysfsService.readDeviceProductName(),
    _sysfsService.readDeviceSerial(),
    _sysfsService.readBiosVersion(),
  ]);
  return DeviceIdentitySnapshot(
    productFamily: results[0] as String?,
    productName: results[1] as String?,
    serial: results[2] as String?,
    biosVersion: results[3] as String?,
  );
}
```

**Step 6: Create device header widget**

`lib/features/dashboard/widgets/device_identity_card.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';
import '../models/device_identity_snapshot.dart';

class DeviceIdentityCard extends StatelessWidget {
  const DeviceIdentityCard({super.key, required this.identity});

  final DeviceIdentitySnapshot identity;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    final metaItems = [
      if (identity.serial != null) 'Serial: ${identity.serial}',
      if (identity.productName != null) 'Product: ${identity.productName}',
      if (identity.biosVersion != null) 'BIOS: ${identity.biosVersion}',
    ].join('  ·  ');

    return YaruSection(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(identity.displayName, style: textTheme.headlineSmall),
            if (metaItems.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                metaItems,
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

**Step 7: Run tests**

```bash
flutter test test/features/dashboard/device_identity_snapshot_test.dart -v
flutter test -v
```

**Step 8: Commit**

```bash
git add lib/features/dashboard/models/device_identity_snapshot.dart \
        lib/features/dashboard/models/dashboard_snapshot.dart \
        lib/features/dashboard/repository/dashboard_repository.dart \
        lib/features/dashboard/widgets/device_identity_card.dart \
        test/features/dashboard/device_identity_snapshot_test.dart
git commit -m "feat(dashboard): add DeviceIdentitySnapshot + device header card"
```

---

### Task 8: Dashboard sensor strip widget

**Files:**
- Create: `lib/features/dashboard/widgets/sensor_strip.dart`

**Context:** Two-column CPU/GPU strip + secondary single-row strip (motherboard, battery, disk). Uses `LiveSensorSnapshot`. Shows a sensor only when non-null — graceful degradation. No tests needed (pure display widget); verify visually.

**Step 1: Create `lib/features/dashboard/widgets/sensor_strip.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';
import '../../sensors/models/live_sensor_snapshot.dart';

class SensorStrip extends StatelessWidget {
  const SensorStrip({super.key, required this.snapshot});

  final LiveSensorSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return YaruSection(
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _CpuColumn(snapshot: snapshot)),
              const SizedBox(width: 16),
              Expanded(child: _GpuColumn(snapshot: snapshot)),
            ],
          ),
          const SizedBox(height: 8),
          _SecondaryRow(snapshot: snapshot),
        ],
      ),
    );
  }
}

class _CpuColumn extends StatelessWidget {
  const _CpuColumn({required this.snapshot});
  final LiveSensorSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return _SensorColumn(
      name: snapshot.cpuName ?? 'CPU',
      rows: [
        if (snapshot.cpuUtilPercent != null)
          _SensorRow('Utilisation', '${snapshot.cpuUtilPercent!.toStringAsFixed(0)} %'),
        if (snapshot.cpuClockGhz != null)
          _SensorRow('Core Clock', '${snapshot.cpuClockGhz!.toStringAsFixed(2)} GHz'),
        if (snapshot.cpuTempC != null)
          _SensorRow('Temperature', '${snapshot.cpuTempC!.toStringAsFixed(0)} °C',
            highlight: _tempColor(context, snapshot.cpuTempC!)),
        if (snapshot.fan1Rpm != null)
          _SensorRow('Fan', '${snapshot.fan1Rpm} RPM'),
      ],
    );
  }
}

class _GpuColumn extends StatelessWidget {
  const _GpuColumn({required this.snapshot});
  final LiveSensorSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final label = snapshot.gpuIsDiscrete ? 'dGPU' : 'iGPU';
    return _SensorColumn(
      name: snapshot.gpuName ?? label,
      rows: [
        if (snapshot.gpuUtilPercent != null)
          _SensorRow('Utilisation', '${snapshot.gpuUtilPercent!.toStringAsFixed(0)} %'),
        if (snapshot.gpuClockGhz != null)
          _SensorRow('Core Clock', '${snapshot.gpuClockGhz!.toStringAsFixed(2)} GHz'),
        if (snapshot.gpuTempC != null)
          _SensorRow('Temperature', '${snapshot.gpuTempC!.toStringAsFixed(0)} °C',
            highlight: _tempColor(context, snapshot.gpuTempC!)),
        if (snapshot.gpuFanRpm != null)
          _SensorRow('Fan', '${snapshot.gpuFanRpm} RPM'),
        if (snapshot.gpuVramUsedGb != null && snapshot.gpuVramTotalGb != null)
          _SensorRow('VRAM',
            '${snapshot.gpuVramUsedGb!.toStringAsFixed(1)} / ${snapshot.gpuVramTotalGb!.toStringAsFixed(0)} GB'),
        if (snapshot.gpuPowerDrawW != null)
          _SensorRow('Power', '${snapshot.gpuPowerDrawW!.toStringAsFixed(0)} W'),
      ],
    );
  }
}

class _SensorColumn extends StatelessWidget {
  const _SensorColumn({required this.name, required this.rows});
  final String name;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        ...rows,
      ],
    );
  }
}

class _SensorRow extends StatelessWidget {
  const _SensorRow(this.label, this.value, {this.highlight});
  final String label;
  final String value;
  final Color? highlight;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
            style: textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
          Text(value,
            style: textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: highlight,
            ),
          ),
        ],
      ),
    );
  }
}

class _SecondaryRow extends StatelessWidget {
  const _SecondaryRow({required this.snapshot});
  final LiveSensorSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final items = <String>[];
    if (snapshot.motherboardTempC != null) {
      items.add('Motherboard  ${snapshot.motherboardTempC!.toStringAsFixed(0)}°C');
    }
    if (snapshot.batteryPercent != null) {
      final state = snapshot.batteryCharging == true ? 'Charging' : 'Discharging';
      final draw = snapshot.batteryPowerDrawW != null
          ? '  ${snapshot.batteryPowerDrawW!.toStringAsFixed(0)}W'
          : '';
      items.add('Battery  ${snapshot.batteryPercent}%  $state$draw');
    }
    if (snapshot.diskTempC != null) {
      items.add('Disk  ${snapshot.diskTempC!.toStringAsFixed(0)}°C');
    }
    if (items.isEmpty) return const SizedBox.shrink();

    return Text(
      items.join('   ·   '),
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
      ),
    );
  }
}

Color? _tempColor(BuildContext context, double tempC) {
  if (tempC >= 85) return Colors.red;
  if (tempC >= 70) return Colors.orange;
  return null;
}
```

**Step 2: Commit**

```bash
git add lib/features/dashboard/widgets/sensor_strip.dart
git commit -m "feat(dashboard): add SensorStrip widget for live CPU/GPU/battery display"
```

---

### Task 9: Full dashboard page rewrite

**Files:**
- Modify: `lib/features/dashboard/view/dashboard_page.dart`
- Modify: `lib/features/dashboard/providers/dashboard_provider.dart` (add liveSensor)

**Context:** The dashboard now has 5 zones:
1. Device identity card (from Task 7)
2. Live sensor strip (from Task 8 — watches `liveSensorBlocProvider`)
3. Status line below the AppPageBody title (power mode · hybrid · temp · power source)
4. 2-column `Wrap` of `DashboardCard` control cards
5. Bottom navigation strip

**Step 1: Ensure `LiveSensorStarted` is dispatched in `dashboard_page.dart`**

In `initState` equivalent (or in `build` using `ref.listen`), add:
```dart
ref.read(liveSensorBlocProvider.bloc).add(const LiveSensorStarted());
```

**Step 2: Rewrite `lib/features/dashboard/view/dashboard_page.dart`**

The complete rewrite implements all 5 zones. Key structure:

```dart
class DashboardPage extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dashboardBlocProvider);
    final sensorState = ref.watch(liveSensorBlocProvider);
    // Dispatch started events on first build.
    // ...

    final snapshot = state.snapshot;
    final sensors = sensorState.snapshot;

    return AppPageBody(
      title: 'Legion Control Center',
      subtitle: _buildStatusLine(snapshot, sensors), // new optional param
      errorMessage: state.errorMessage,
      noticeMessage: state.noticeMessage,
      children: [
        // Zone 1: Device identity
        DeviceIdentityCard(identity: snapshot.deviceIdentity),
        const SizedBox(height: 16),

        // Zone 2: Sensor strip
        SensorStrip(snapshot: sensors),
        const SizedBox(height: 16),

        // Zone 4: Control cards (2-column Wrap)
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(
              width: _cardWidth(context),
              child: _PowerModeCard(snapshot: snapshot, state: state, ref: ref),
            ),
            SizedBox(
              width: _cardWidth(context),
              child: _GraphicsModeCard(snapshot: snapshot, state: state, ref: ref),
            ),
            SizedBox(
              width: _cardWidth(context),
              child: _BatteryCard(snapshot: snapshot, state: state, ref: ref),
            ),
            SizedBox(
              width: _cardWidth(context),
              child: _QuickActionsCard(snapshot: snapshot, state: state, ref: ref),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Zone 5: Section nav strip
        _SectionNavStrip(),
      ],
    );
  }
}
```

Add `subtitle` param to `AppPageBody` (optional `Widget? subtitle` displayed below the title as `bodySmall` text).

Each `_*Card` is a private `StatelessWidget` using `DashboardCard`. For example, `_PowerModeCard`:

```dart
class _PowerModeCard extends StatelessWidget {
  // ... snapshot, state, ref ...
  @override
  Widget build(BuildContext context) {
    final mode = snapshot.status.powerProfile?.trim() ?? '';
    final tint = _modeColor(mode, context);
    return DashboardCard(
      icon: _modeIcon(mode),
      title: _modeTitle(mode),
      tint: tint,
      children: [
        Text(_modeDescription(mode),
          style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        YaruChoiceChipBar(
          labels: snapshot.availablePowerModes
              .map((m) => Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_modeIcon(m), size: 14),
                    const SizedBox(width: 4),
                    Text(m),
                  ]))
              .toList(),
          isSelected: snapshot.availablePowerModes
              .map((m) => mode == m)
              .toList(),
          onSelected: state.isApplying ? null : (i) async { /* confirm + dispatch */ },
        ),
      ],
    );
  }

  IconData _modeIcon(String mode) {
    if (mode.contains('quiet')) return Icons.nightlight_outlined;
    if (mode.contains('performance')) return Icons.rocket_launch_outlined;
    return Icons.balance_outlined;
  }

  Color? _modeColor(String mode, BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (mode.contains('performance')) return scheme.primary;
    if (mode.contains('quiet')) return Colors.blueGrey;
    return null;
  }

  String _modeTitle(String mode) {
    if (mode.contains('quiet')) return 'Quiet Mode';
    if (mode.contains('performance')) return 'Performance Mode';
    return 'Balanced Mode';
  }

  String _modeDescription(String mode) {
    if (mode.contains('quiet')) return 'Low noise · Battery friendly';
    if (mode.contains('performance')) return 'Maximum power · Gaming';
    return 'Smart cooling · Everyday use';
  }
}
```

**Step 3: Add `subtitle` support to `AppPageBody`**

In `lib/core/widgets/app_shell_components.dart`, add optional `Widget? subtitle` param to `AppPageBody.build()`. Render it below the title.

**Step 4: Run tests + visual check**

```bash
flutter test -v
flutter run -d linux
```

**Step 5: Commit**

```bash
git add lib/features/dashboard/ lib/core/widgets/app_shell_components.dart
git commit -m "feat(dashboard): rewrite with device identity, sensor strip, and control cards"
```

---

## Phase 4 — Bloc Splits

### Task 10: Split DisplayLightingBloc → DisplayBloc + LightingBloc

**Files:**
- Create: `lib/features/display/` (full feature dir)
- Create: `lib/features/lighting/` (full feature dir)
- Keep: `lib/features/display_lighting/` (delete after Task 12+13 are done)

**Context:** `DisplayLightingRepository` currently handles hybrid mode, overdrive, refresh rate, keyboard backlight, Y-logo, IO port light. Hybrid mode moves to Dgpu. Display keeps: overdrive, refresh rate. Lighting keeps: keyboard backlight, Y-logo, IO port.

**Step 1: Write bloc tests for DisplayBloc**

```dart
// test/features/display/display_bloc_test.dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:legion_frontend/features/display/bloc/display_bloc.dart';
import 'package:legion_frontend/features/display/bloc/display_event.dart';
import 'package:legion_frontend/features/display/bloc/display_state.dart';
import 'package:legion_frontend/features/display/models/display_snapshot.dart';
import 'package:legion_frontend/features/display/repository/display_repository.dart';

class MockDisplayRepository extends Mock implements DisplayRepository {}

void main() {
  late MockDisplayRepository repo;

  setUp(() => repo = MockDisplayRepository());

  final snapshot = DisplaySnapshot(
    overdriveEnabled: false,
    overdriveSupported: true,
    xrandrOutputName: 'eDP-1',
    availableRefreshRates: const [60.0, 165.0],
    currentRefreshRate: 165.0,
  );

  blocTest<DisplayBloc, DisplayState>(
    'emits loaded snapshot on DisplayStarted',
    build: () {
      when(() => repo.loadSnapshot()).thenAnswer((_) async => snapshot);
      return DisplayBloc(
        repository: repo,
        pollInterval: const Duration(seconds: 60),
      );
    },
    act: (bloc) => bloc.add(const DisplayStarted()),
    wait: const Duration(milliseconds: 100),
    expect: () => [
      DisplayState(
        overdriveEnabled: false,
        overdriveSupported: true,
        xrandrOutputName: 'eDP-1',
        availableRefreshRates: const [60.0, 165.0],
        currentRefreshRate: 165.0,
        isLoading: false,
      ),
    ],
  );
}
```

**Step 2: Create Display feature**

Create the full `lib/features/display/` directory tree with:
- `models/display_snapshot.dart` — fields: `overdriveEnabled`, `overdriveSupported`, `xrandrOutputName`, `availableRefreshRates`, `currentRefreshRate`
- `repository/display_repository.dart` — `loadSnapshot()`, `setOverdriveMode()`, `setRefreshRate()`; extracted from `DisplayLightingRepository`
- `bloc/display_event.dart` — `DisplayStarted`, `DisplayRefreshRequested`, `DisplayTicked`, `OverdriveModeSetRequested`, `RefreshRateSetRequested`
- `bloc/display_state.dart`
- `bloc/display_bloc.dart` — same polling pattern as other blocs
- `providers/display_provider.dart`

**Step 3: Create Lighting feature**

Create `lib/features/lighting/` with:
- `models/lighting_snapshot.dart` — `whiteKeyboardBacklightEnabled/Supported`, `yLogoLightEnabled/Supported`, `ioPortLightEnabled/Supported`
- `repository/lighting_repository.dart`
- `bloc/` + `providers/` (same pattern)

**Step 4: Run tests**

```bash
flutter test test/features/display/ test/features/lighting/ -v
flutter test -v
```

**Step 5: Commit**

```bash
git add lib/features/display/ lib/features/lighting/ \
        test/features/display/ test/features/lighting/
git commit -m "feat(display,lighting): split DisplayLightingBloc into DisplayBloc + LightingBloc"
```

---

### Task 11: Split BatteryDevicesBloc → BatteryBloc + DevicesBloc

**Files:**
- Create: `lib/features/battery/` (new, battery-only)
- Create: `lib/features/devices/` (new, input/USB device toggles)
- Keep: `lib/features/battery_devices/` (used as stub until Tasks 14+15)

**Context:** `BatteryDevicesBloc` currently handles battery conservation, rapid charging, always-on USB, touchpad, win key, fn lock. Battery keeps: conservation, rapid charging. Devices keeps: always-on USB, touchpad, win key, fn lock, camera.

Battery also gains new sysfs reads for health data: `readBatteryCycleCount()`, `readBatteryFullCapacityWh()`, etc. (already added in Task 5).

**Step 1: Write bloc tests for BatteryBloc**

```dart
// test/features/battery/battery_bloc_test.dart
// (same pattern as display_bloc_test.dart — test Started/Ticked/error)
```

**Step 2: Create `lib/features/battery/`**

- `models/battery_snapshot.dart`:
```dart
class BatterySnapshot extends Equatable {
  // Level, charging state, power draw, conservation, rapid charging,
  // health fields: full capacity Wh, design capacity Wh,
  // current capacity Wh, cycle count, battery temp C.
}
```

- `repository/battery_repository.dart` — loads all battery fields in parallel from sysfs
- `bloc/` + `providers/` (standard pattern)

**Step 3: Create `lib/features/devices/`**

- `models/devices_snapshot.dart`
- `repository/devices_repository.dart`
- `bloc/` + `providers/`

**Step 4: Run tests + commit**

```bash
flutter test test/features/battery/ test/features/devices/ -v
flutter test -v
git add lib/features/battery/ lib/features/devices/ \
        test/features/battery/ test/features/devices/
git commit -m "feat(battery,devices): split BatteryDevicesBloc into BatteryBloc + DevicesBloc"
```

---

## Phase 5 — Feature Pages

### Task 12: Display page

**Files:**
- Create: `lib/features/display/view/display_page.dart`
- Modify: `lib/features/navigation/view/navigation_shell.dart` (wire up)

Replace the stub `AppSection.display → DisplayLightingPage` with the new `DisplayPage`. Page has two `AppControlCard` sections: Overdrive and Refresh Rate.

**Commit:** `feat(display): add Display page with overdrive and refresh rate controls`

---

### Task 13: Lighting page

**Files:**
- Create: `lib/features/lighting/view/lighting_page.dart`
- Modify: `lib/features/navigation/view/navigation_shell.dart`

Three `AppControlCard` items: Keyboard Backlight (toggle + OpenRGB placeholder), Y-Logo Light, IO Port Light.

OpenRGB placeholder:
```dart
YaruBanner.tile(
  color: scheme.surfaceContainerHighest,
  title: const Text('Per-key RGB (OpenRGB)'),
  subtitle: const Text('OpenRGB integration coming in a future update.'),
  icon: const Icon(Icons.keyboard_outlined),
)
```

**Commit:** `feat(lighting): add Lighting page with backlight toggles and OpenRGB placeholder`

---

### Task 14: Battery page (full)

**Files:**
- Create: `lib/features/battery/view/battery_page.dart`
- Modify: `lib/features/navigation/view/navigation_shell.dart`

Layout:
1. **Status header** — battery icon (use `YaruIcons.battery_*` variant based on %) + `"78%"` in `headlineLarge` + charging state
2. **Health `AppControlCard`** — current/full/design capacity (Wh), health %, cycle count, temperature
3. **Live `AppControlCard`** — power draw W, on battery since (if available)
4. **Controls `AppControlCard`** — Battery Conservation `YaruSwitchListTile` + Rapid Charging `YaruSwitchListTile`

**Commit:** `feat(battery): add full Battery page with health, live stats, and controls`

---

### Task 15: Devices page

**Files:**
- Create: `lib/features/devices/view/devices_page.dart`
- Modify: `lib/features/navigation/view/navigation_shell.dart`

Three `AppControlCard` sections: Input (Touchpad, Win Key, Fn Lock), Power (Always-on USB), Camera.

**Commit:** `feat(devices): add Devices page with input/USB/camera toggles`

---

### Task 16: Power page redesign

**Files:**
- Modify: `lib/features/power/view/power_page.dart`

Changes:
- Mode selector replaced with `AppControlCard` containing a `YaruChoiceChipBar` with icon+label per mode and a mode description line below
- Power limits wrapped in a `YaruExpandable` (collapsed by default, labelled "Advanced: Power Limits")
- CPU/GPU overclock remain as `AppControlCard` sections
- All `AppSectionCard` → `AppControlCard` with icons

**Commit:** `feat(power): redesign Power page with icon mode selector and collapsible limits`

---

### Task 17: Fans page redesign

**Files:**
- Modify: `lib/features/fans/view/fans_page.dart`

Changes:
- Remove the existing preset dropdown. Replace with action row at the top:
  ```dart
  Row(children: [
    Expanded(child: OutlinedButton.icon(
      onPressed: _onMaxFanSpeed,
      icon: Icon(YaruIcons.gears),
      label: Text(state.maximumFanSpeedEnabled ? 'Max Fan: On' : 'Max Fan Speed'),
      style: state.maximumFanSpeedEnabled
          ? OutlinedButton.styleFrom(foregroundColor: scheme.primary)
          : null,
    )),
    const SizedBox(width: 12),
    Expanded(child: FilledButton.icon(
      onPressed: _onApplyPreset,
      icon: const Icon(Icons.tune),
      label: const Text('Apply Preset'),
    )),
  ])
  ```
- "Apply Preset" opens a `YaruDialog` listing presets with name + description, recommended highlighted
- Fan curve editor: replace the table widget with an `fl_chart` `LineChart`. X-axis 0–100°C, Y-axis 0–max RPM. Draggable points using `GestureDetector` on `LineTooltipItem`
- Controls card: Mini Fan Curve + Lock Fan Controller as `AppControlCard` items

**Note on fan curve graph:** `fl_chart` `LineChart` with `titlesData`, `lineBarsData` (one for fan1, one for fan2). For draggable points, render `FlSpot` for each of the 10 curve points. Use `GestureDetector` wrapping the chart to intercept pan events and map to nearest point index.

**Commit:** `feat(fans): redesign Fans page with action row, preset dialog, and fl_chart curve editor`

---

### Task 18: Discrete GPU page expansion

**Files:**
- Modify: `lib/features/dgpu/view/dgpu_page.dart`
- Modify: `lib/features/dgpu/bloc/dgpu_bloc.dart` + repository (add hybrid mode)

Changes:
1. **Stats `AppControlCard`** — watches `liveSensorBlocProvider` for GPU stats when `gpuIsDiscrete` is true. Shows name, utilisation, clock, temp, fan, VRAM, power draw.
2. **Processes `AppControlCard`** — existing process list + Kill All button
3. **PCI `AppControlCard`** — existing restart PCI button
4. **Performance `AppControlCard`** — GPU Overclock toggle (from PowerBloc)
5. **Hybrid Mode `AppControlCard`** (moved from Display) — toggle + "Reboot required" notice

For Hybrid Mode, add it to `DgpuRepository` (or keep using `DashboardRepository.setHybridMode` via a cross-feature call — simplest is to duplicate the sysfs write in `DgpuRepository`).

**Commit:** `feat(dgpu): expand GPU page with live stats, hybrid mode, and overclock`

---

### Task 19: Automation page redesign

**Files:**
- Modify: `lib/features/automation/view/automation_page.dart`

Visual-only redesign — no bloc/repository changes. Replace flat list with:
1. Enable toggle `AppControlCard` at top
2. **Rules section**: each rule is a `YaruExpandable`. Header: trigger label + step count. Expanded: `YaruTile` per step (icon + name + description + action dropdown). Action row: `[Run now]  [Add step]  [Delete]  Exclusive □  Run on startup □`
3. **Quick Actions section**: same expandable pattern
4. `FilledButton('Add new')` at bottom of each section

Take visual inspiration from LLT screenshots (shared in design conversation).

**Commit:** `feat(automation): redesign Automation page with expandable rules and LLT-style layout`

---

### Task 20: Settings page additions

**Files:**
- Modify: `lib/features/settings/view/settings_page.dart`
- Modify: `lib/features/settings/bloc/settings_bloc.dart` + state (add themeMode + yaruVariant)

New `AppControlCard` at top of page: **Appearance**
- Theme mode: `YaruChoiceChipBar` with `[System]  [Light]  [Dark]`
- Yaru accent colour: a grid of `YaruColorDisk` or `ColoredBox` circles for each `YaruVariant` value

New `AppControlCard` at bottom: **Boot Logo** (absorbed from `BootLogoPage`)
- Image picker + upload button

For theme/accent to actually apply, the `YaruTheme` in `app.dart` must read from `settingsBlocProvider`:
```dart
YaruTheme(
  builder: (context, yaru, child) {
    final settings = ref.watch(settingsBlocProvider);
    return MaterialApp(
      themeMode: settings.themeMode,
      theme: yaru.theme?.copyWith(/* accent from settings.yaruVariant */),
      darkTheme: yaru.darkTheme,
      // ...
    );
  },
);
```

Check `YaruTheme` API for how to set accent — it may be via `YaruThemeData.variant`.

**Commit:** `feat(settings): add Appearance card with theme mode + accent colour, absorb Boot Logo`

---

### Task 21: Diagnostics page (merged Analytics + About)

**Files:**
- Create: `lib/features/diagnostics/view/diagnostics_page.dart`
- Modify: `lib/features/navigation/view/navigation_shell.dart` (wire up, remove About stub)

Layout (single `AppPageBody`, two halves):

**Top half — Live Sensors** (reuses `AnalyticsBloc`):
- Temperature line chart (CPU + GPU over last N minutes) — existing `AnalyticsPage` chart code moved here
- Fan RPM chart

**Bottom half — System Info** (reuses `AboutBloc`):
- Environment `AppSectionCard` — kernel, hardware model, module version, CLI version
- Command History `AppSectionCard` — last 20 commands (redacted)
- Copy JSON button

Both `AnalyticsStarted` and `AboutStarted` events dispatched in `initState`.

**Commit:** `feat(diagnostics): add Diagnostics page merging Analytics + About`

---

### Task 22: Final cleanup and full test run

**Files:**
- Remove stubs in `NavigationShell._buildPage()` (replace all temporary `DisplayLightingPage`, `BatteryDevicesPage`, `AboutPage` stubs with actual new pages)
- Run `flutter analyze` and fix any warnings
- Delete dead code: `lib/features/about/` and `lib/features/analytics/` can be kept but removed from navigation (they're now merged into diagnostics)

**Step 1: Full test run**

```bash
flutter test --reporter=expanded
```

Expected: All pass.

**Step 2: Analyse**

```bash
flutter analyze
```

Fix any warnings.

**Step 3: Final commit**

```bash
git add -u
git commit -m "chore(nav): wire all new pages, remove stubs, final cleanup"
```
