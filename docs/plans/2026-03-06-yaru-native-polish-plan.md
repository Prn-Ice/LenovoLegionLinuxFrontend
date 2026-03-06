# Yaru-Native UX Polish Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace Material navigation and generic widgets with Yaru-native equivalents so the app looks and feels like a native GNOME/Ubuntu application.

**Architecture:** Two commits following Approach A — navigation shell first (one file, high visual impact), then shared components and per-page widget sweep. The `YaruPageController` bridges the Yaru nav widgets with the existing Riverpod BLoC so that programmatic navigation (e.g. dashboard "Open Battery" buttons) keeps working after the shell migration.

**Tech Stack:** Flutter, Riverpod, yaru ^9.0.1 (already a dependency), BLoC via riverbloc

---

## Task 1: Navigation Shell

**Files:**
- Modify: `lib/features/navigation/models/app_section.dart`
- Modify: `lib/main.dart`
- Modify: `lib/features/navigation/view/navigation_shell.dart`

### Step 1: Add `yaruIcon` getter to `AppSection`

Open `lib/features/navigation/models/app_section.dart`. Add `import 'package:yaru/yaru.dart';` at the top, then add a new getter inside `AppSectionUi`:

```dart
import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

enum AppSection {
  dashboard,
  power,
  fans,
  battery,
  displayLighting,
  automation,
  settings,
  about,
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
        return 'Battery & Devices';
      case AppSection.displayLighting:
        return 'Display & Lighting';
      case AppSection.automation:
        return 'Automation';
      case AppSection.settings:
        return 'Settings';
      case AppSection.about:
        return 'About';
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
      case AppSection.displayLighting:
        return Icons.display_settings_outlined;
      case AppSection.automation:
        return Icons.auto_mode_outlined;
      case AppSection.settings:
        return Icons.settings_outlined;
      case AppSection.about:
        return Icons.info_outline;
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
      case AppSection.displayLighting:
        return YaruIcons.display_layout;
      case AppSection.automation:
        return YaruIcons.gear_dots;
      case AppSection.settings:
        return YaruIcons.gear;
      case AppSection.about:
        return YaruIcons.information;
    }
  }
}
```

### Step 2: Update `main.dart` to initialize window title bar

Replace `lib/main.dart` with:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import 'app/app.dart';

Future<void> main() async {
  await YaruWindowTitleBar.ensureInitialized();
  runApp(const ProviderScope(child: LegionFrontendApp()));
}
```

### Step 3: Rewrite `navigation_shell.dart`

Replace the entire file with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../about/view/about_page.dart';
import '../../automation/view/automation_page.dart';
import '../../battery_devices/view/battery_devices_page.dart';
import '../../dashboard/view/dashboard_page.dart';
import '../../display_lighting/view/display_lighting_page.dart';
import '../../fans/view/fans_page.dart';
import '../../power/view/power_page.dart';
import '../../settings/view/settings_page.dart';
import '../bloc/navigation_event.dart';
import '../models/app_section.dart';
import '../providers/navigation_provider.dart';

class NavigationShell extends ConsumerStatefulWidget {
  const NavigationShell({super.key});

  static const List<AppSection> _sections = AppSection.values;

  @override
  ConsumerState<NavigationShell> createState() => _NavigationShellState();
}

class _NavigationShellState extends ConsumerState<NavigationShell> {
  late final YaruPageController _controller;

  @override
  void initState() {
    super.initState();
    final initial = ref.read(navigationBlocProvider).section;
    _controller = YaruPageController(
      length: NavigationShell._sections.length,
      initialIndex: initial.index,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Sync controller when navigation is driven externally (e.g. dashboard buttons).
    ref.listen(navigationBlocProvider, (prev, next) {
      if (prev?.section != next.section) {
        _controller.index = next.section.index;
      }
    });

    final bloc = ref.read(navigationBlocProvider.bloc);
    final width = MediaQuery.of(context).size.width;

    void onSelected(int index) {
      bloc.add(NavigationSectionSelected(NavigationShell._sections[index]));
    }

    if (width < kYaruMasterDetailBreakpoint) {
      final style = width > 1000
          ? YaruNavigationRailStyle.labelledExtended
          : width > 500
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
          controller: _controller,
          itemBuilder: (context, index, selected) => YaruNavigationRailItem(
            icon: Icon(NavigationShell._sections[index].yaruIcon),
            label: Text(NavigationShell._sections[index].label),
            tooltip: NavigationShell._sections[index].label,
            style: style,
          ),
          pageBuilder: (context, index) =>
              _buildPage(NavigationShell._sections[index]),
          onSelected: onSelected,
        ),
      );
    }

    return YaruMasterDetailPage(
      controller: _controller,
      paneLayoutDelegate: const YaruResizablePaneDelegate(
        initialPaneSize: 280,
        minPageSize: kYaruMasterDetailBreakpoint / 2,
        minPaneSize: 175,
      ),
      tileBuilder: (context, index, selected, availableWidth) => YaruMasterTile(
        leading: Icon(NavigationShell._sections[index].yaruIcon),
        title: Text(NavigationShell._sections[index].label),
      ),
      pageBuilder: (context, index) => YaruDetailPage(
        appBar: YaruWindowTitleBar(
          border: BorderSide.none,
          leading: Navigator.of(context).canPop()
              ? const YaruBackButton()
              : null,
          title: Text(NavigationShell._sections[index].label),
        ),
        body: _buildPage(NavigationShell._sections[index]),
      ),
      appBar: YaruWindowTitleBar(
        title: const Text('Lenovo Legion Linux'),
        border: BorderSide.none,
        backgroundColor: YaruMasterDetailTheme.of(context).sideBarColor,
      ),
      onSelected: onSelected,
    );
  }

  Widget _buildPage(AppSection section) {
    switch (section) {
      case AppSection.dashboard:
        return const DashboardPage();
      case AppSection.power:
        return const PowerPage();
      case AppSection.fans:
        return const FansPage();
      case AppSection.battery:
        return const BatteryDevicesPage();
      case AppSection.displayLighting:
        return const DisplayLightingPage();
      case AppSection.automation:
        return const AutomationPage();
      case AppSection.settings:
        return const SettingsPage();
      case AppSection.about:
        return const AboutPage();
    }
  }
}
```

### Step 4: Run the tests

```bash
cd frontend/legion_frontend && flutter test
```

Expected: both existing widget tests pass. The `find.text('Power')` finder still works because `YaruMasterTile` renders a `Text` widget.

If a test fails with a `Navigator` or `YaruWindowTitleBar` initialization error, wrap the test pump with `await tester.pumpAndSettle()` instead of `await tester.pump()`.

### Step 5: Commit

```bash
git add frontend/legion_frontend/lib/features/navigation/models/app_section.dart \
        frontend/legion_frontend/lib/features/navigation/view/navigation_shell.dart \
        frontend/legion_frontend/lib/main.dart
git commit -m "feat: migrate navigation shell to YaruMasterDetailPage and YaruNavigationPage

Replace Material NavigationRail/NavigationBar with Yaru-native navigation.
Wide layout uses YaruMasterDetailPage with a resizable sidebar; compact
layout uses YaruNavigationPage with an adaptive rail style. YaruWindowTitleBar
added to both layouts. YaruPageController bridges the Yaru widgets with the
existing Riverpod navigation BLoC so programmatic navigation keeps working.
Section icons migrated from Icons.* to YaruIcons.*.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 2: Shared Components and Page Widgets

**Files:**
- Modify: `lib/core/widgets/app_shell_components.dart`
- Modify: `lib/features/dashboard/view/dashboard_page.dart`
- Modify: `lib/features/power/view/power_page.dart`
- Modify: `lib/features/fans/view/fans_page.dart`
- Modify: `lib/features/automation/view/automation_page.dart`
- Modify: `lib/features/display_lighting/view/display_lighting_page.dart`
- Modify: `lib/features/battery_devices/view/battery_devices_page.dart`
- Modify: `lib/features/settings/view/settings_page.dart`
- Modify: `lib/features/about/view/about_page.dart`

### Step 1: Update `app_shell_components.dart`

Replace the entire file with the following. Key changes:
- `AppSectionCard` uses `YaruSection` instead of `Card`
- `AppSwitchTile` uses `YaruSwitchListTile`
- `AppPageBody` uses `kYaruPagePadding` (15.0) instead of hardcoded 24
- `AppRefreshButton` uses `YaruCircularProgressIndicator`

```dart
import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';

enum AppStatusTone { error, notice }

class AppPageBody extends StatelessWidget {
  const AppPageBody({
    super.key,
    required this.title,
    this.errorMessage,
    this.noticeMessage,
    required this.children,
  });

  final String title;
  final String? errorMessage;
  final String? noticeMessage;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.all(kYaruPagePadding),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: textTheme.headlineMedium),
                const SizedBox(height: 16),
                if (errorMessage != null || noticeMessage != null) ...[
                  AppStatusMessages(
                    errorMessage: errorMessage,
                    noticeMessage: noticeMessage,
                  ),
                  const SizedBox(height: 12),
                ],
                ...children,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class AppStatusMessages extends StatelessWidget {
  const AppStatusMessages({super.key, this.errorMessage, this.noticeMessage});

  final String? errorMessage;
  final String? noticeMessage;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (errorMessage != null)
          AppStatusBanner(message: errorMessage!, tone: AppStatusTone.error),
        if (errorMessage != null && noticeMessage != null)
          const SizedBox(height: 8),
        if (noticeMessage != null)
          AppStatusBanner(message: noticeMessage!, tone: AppStatusTone.notice),
      ],
    );
  }
}

class AppStatusBanner extends StatelessWidget {
  const AppStatusBanner({super.key, required this.message, required this.tone});

  final String message;
  final AppStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isError = tone == AppStatusTone.error;

    final backgroundColor = isError
        ? scheme.errorContainer
        : scheme.primaryContainer;
    final foregroundColor = isError
        ? scheme.onErrorContainer
        : scheme.onPrimaryContainer;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: foregroundColor.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.info_outline,
            size: 18,
            color: foregroundColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: TextStyle(color: foregroundColor)),
          ),
        ],
      ),
    );
  }
}

class AppSectionCard extends StatelessWidget {
  const AppSectionCard({
    super.key,
    required this.title,
    this.description,
    this.trailing,
    required this.children,
  });

  final String title;
  final String? description;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return YaruSection(
      headline: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Expanded(child: Text(title, style: textTheme.titleMedium)),
            if (trailing != null) trailing!,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (description != null) ...[
            Text(description!),
            const SizedBox(height: 8),
          ],
          if (children.isNotEmpty) ...children,
        ],
      ),
    );
  }
}

class AppRefreshButton extends StatelessWidget {
  const AppRefreshButton({
    super.key,
    required this.isBusy,
    this.onPressed,
    this.label = 'Refresh',
  });

  final bool isBusy;
  final VoidCallback? onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: isBusy ? null : onPressed,
      icon: isBusy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: YaruCircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh),
      label: Text(label),
    );
  }
}

class AppSwitchTile extends StatelessWidget {
  const AppSwitchTile({
    super.key,
    required this.value,
    required this.title,
    this.subtitle,
    this.onChanged,
    this.contentPadding = EdgeInsets.zero,
  });

  final bool value;
  final String title;
  final String? subtitle;
  final ValueChanged<bool>? onChanged;
  final EdgeInsetsGeometry contentPadding;

  @override
  Widget build(BuildContext context) {
    return YaruSwitchListTile(
      contentPadding: contentPadding,
      value: value,
      onChanged: onChanged,
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
    );
  }
}

String boolEnabledLabel(
  bool? value, {
  String unavailableLabel = 'Unavailable on this device',
}) {
  if (value == null) {
    return unavailableLabel;
  }

  return value ? 'Enabled' : 'Disabled';
}
```

### Step 2: Update `dashboard_page.dart` — replace `ChoiceChip` Wrap with `YaruChoiceChipBar`

In `lib/features/dashboard/view/dashboard_page.dart`, find the `Wrap` of `ChoiceChip` widgets inside the "Quick Actions" card and replace it:

**Before:**
```dart
if (snapshot.availablePowerModes.isEmpty)
  const Text('No writable power modes available.')
else
  Wrap(
    spacing: 8,
    runSpacing: 8,
    children: snapshot.availablePowerModes
        .map(
          (mode) => ChoiceChip(
            label: Text(mode),
            selected: snapshot.status.powerProfile?.trim() == mode,
            onSelected: state.isApplying
                ? null
                : (selected) async {
                    if (selected) {
                      final confirmed = await confirmPrivilegedAction(
                        context,
                        title: 'Set power mode',
                        message:
                            'Changing power mode runs a privileged command and may prompt for authentication.',
                        confirmLabel: 'Set mode',
                      );
                      if (!context.mounted || !confirmed) {
                        return;
                      }
                      bloc.add(
                        DashboardPowerModeSetRequested(mode),
                      );
                    }
                  },
          ),
        )
        .toList(growable: false),
  ),
```

**After:**
```dart
if (snapshot.availablePowerModes.isEmpty)
  const Text('No writable power modes available.')
else
  YaruChoiceChipBar(
    labels: snapshot.availablePowerModes
        .map((mode) => Text(mode))
        .toList(growable: false),
    isSelected: snapshot.availablePowerModes
        .map((mode) => snapshot.status.powerProfile?.trim() == mode)
        .toList(growable: false),
    onSelected: state.isApplying
        ? null
        : (index) async {
            final mode = snapshot.availablePowerModes[index];
            final confirmed = await confirmPrivilegedAction(
              context,
              title: 'Set power mode',
              message:
                  'Changing power mode runs a privileged command and may prompt for authentication.',
              confirmLabel: 'Set mode',
            );
            if (!context.mounted || !confirmed) {
              return;
            }
            bloc.add(DashboardPowerModeSetRequested(mode));
          },
  ),
```

### Step 3: Update `power_page.dart` — `YaruRadioListTile` and `YaruDialogTitleBar`

**3a. Replace `RadioGroup` + `RadioListTile` with `YaruRadioListTile`.**

Find the `RadioGroup<String>` block and replace with a plain `Column`:

```dart
Column(
  children: state.availableModes
      .map(
        (mode) => YaruRadioListTile<String>(
          value: mode.value,
          groupValue: state.currentMode?.value,
          onChanged: state.isApplying
              ? null
              : (value) async {
                  if (value == null) return;
                  final selected = state.availableModes.firstWhere(
                    (entry) => entry.value == value,
                    orElse: () => PowerMode(value),
                  );
                  final confirmed = await confirmPrivilegedAction(
                    context,
                    title: 'Set power mode',
                    message:
                        'Changing power mode uses a privileged command and may prompt for authentication.',
                    confirmLabel: 'Set mode',
                  );
                  if (!context.mounted || !confirmed) return;
                  _setMode(bloc, selected);
                },
          title: Text(mode.label),
          subtitle: Text(mode.value),
        ),
      )
      .toList(growable: false),
),
```

Remove the `RadioGroup` import if it becomes unused.

**3b. Add `YaruDialogTitleBar` to the power limit `AlertDialog`.**

In `_promptAndSetLimit`, change the `AlertDialog` `title:` line:

```dart
// Before:
title: Text(limit.label),

// After:
title: YaruDialogTitleBar(title: Text(limit.label)),
titlePadding: EdgeInsets.zero,
```

### Step 4: Replace `CircularProgressIndicator` with `YaruCircularProgressIndicator` in all pages

Each of the following files has a `Center(child: CircularProgressIndicator())` loading guard at the top of `build`. Replace each one:

```dart
// Before:
return const Center(child: CircularProgressIndicator());

// After:
return const Center(child: YaruCircularProgressIndicator());
```

Files to update (all under `lib/features/`):
- `fans/view/fans_page.dart`
- `automation/view/automation_page.dart`
- `display_lighting/view/display_lighting_page.dart`
- `battery_devices/view/battery_devices_page.dart`
- `settings/view/settings_page.dart`
- `about/view/about_page.dart`

`power_page.dart` also has one — update it there too while editing in Step 3.

Make sure each file already imports `package:yaru/yaru.dart`; add it if missing.

### Step 5: Run the tests

```bash
cd frontend/legion_frontend && flutter test
```

Expected: all tests pass.

### Step 6: Commit

```bash
git add frontend/legion_frontend/lib/core/widgets/app_shell_components.dart \
        frontend/legion_frontend/lib/features/dashboard/view/dashboard_page.dart \
        frontend/legion_frontend/lib/features/power/view/power_page.dart \
        frontend/legion_frontend/lib/features/fans/view/fans_page.dart \
        frontend/legion_frontend/lib/features/automation/view/automation_page.dart \
        frontend/legion_frontend/lib/features/display_lighting/view/display_lighting_page.dart \
        frontend/legion_frontend/lib/features/battery_devices/view/battery_devices_page.dart \
        frontend/legion_frontend/lib/features/settings/view/settings_page.dart \
        frontend/legion_frontend/lib/features/about/view/about_page.dart
git commit -m "feat: replace Material widgets with Yaru-native equivalents

AppSectionCard now uses YaruSection, AppSwitchTile uses YaruSwitchListTile,
AppPageBody uses kYaruPagePadding, and loading spinners use
YaruCircularProgressIndicator. Power page migrates to YaruRadioListTile
and YaruDialogTitleBar. Dashboard power mode selector uses YaruChoiceChipBar.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Verification

After both commits, visually confirm:

1. Wide window (> 800px): sidebar with icons + labels, resizable, `YaruWindowTitleBar` above detail pane
2. Narrow window (< 800px): compact rail that adapts label style as width changes
3. Dashboard "Open Display & Lighting" button navigates correctly (tests the BLoC → controller sync)
4. Power page: radio buttons use Yaru style; power limit dialog has styled title bar
5. All loading states show Yaru spinner
6. `kYaruPagePadding` consistent across all pages
