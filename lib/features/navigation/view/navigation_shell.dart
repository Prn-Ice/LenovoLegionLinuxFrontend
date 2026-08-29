import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../../core/theme/legion_accent.dart';
import '../../../core/widgets/legion_mark.dart';
import '../../../core/widgets/metric_format.dart';
import '../../automation/view/automation_page.dart';
import '../../battery/providers/battery_provider.dart';
import '../../battery/view/battery_page.dart';
import '../../dashboard/bloc/dashboard_event.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import '../../dashboard/view/dashboard_page.dart';
import '../../devices/view/devices_page.dart';
import '../../dgpu/view/dgpu_page.dart';
import '../../diagnostics/view/diagnostics_page.dart';
import '../../display/view/display_page.dart';
import '../../fans/view/fans_page.dart';
import '../../lighting/view/lighting_page.dart';
import '../../power/bloc/power_event.dart';
import '../../power/providers/power_provider.dart';
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
    final initialIndex = NavShellEntries.indexFor(
      ref.read(navigationBlocProvider).section,
    );
    _wideController = YaruPageController(
      length: NavShellEntries.sections.length,
      initialIndex: initialIndex,
    );
    _narrowController = YaruPageController(
      length: NavShellEntries.sections.length,
      initialIndex: initialIndex,
    );
  }

  @override
  void dispose() {
    _wideController.dispose();
    _narrowController.dispose();
    super.dispose();
  }

  void _navigateTo(AppSection section) {
    ref
        .read(navigationBlocProvider.bloc)
        .add(NavigationSectionSelected(section));
  }

  /// Refresh actions live in the title bar rather than page content.
  List<Widget> _titleBarActions(AppSection section) {
    final VoidCallback? onRefresh = switch (section) {
      AppSection.dashboard =>
        () => ref
            .read(dashboardBlocProvider.bloc)
            .add(const DashboardRefreshRequested()),
      AppSection.power =>
        () =>
            ref.read(powerBlocProvider.bloc).add(const PowerRefreshRequested()),
      _ => null,
    };
    if (onRefresh == null) return const [];
    return [
      IconButton(
        icon: const Icon(YaruIcons.refresh, size: 18),
        tooltip: 'Refresh',
        onPressed: onRefresh,
      ),
    ];
  }

  /// Bold style for the window/sidebar titles, matching the design.
  TextStyle? _titleStyle(BuildContext context) => Theme.of(
    context,
  ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700);

  /// Subtle 1px underline beneath the title bars, like the design.
  BorderSide _titleBarBorder(BuildContext context) => BorderSide(
    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
  );

  @override
  Widget build(BuildContext context) {
    // Keep controllers in sync with the navigation bloc.
    ref.listen(navigationBlocProvider, (prev, next) {
      if (prev?.section == next.section) return;
      final idx = NavShellEntries.indexFor(next.section);
      if (_wideController.index != idx) _wideController.index = idx;
      if (_narrowController.index != idx) _narrowController.index = idx;
    });

    // The selected sidebar item re-tints with the current power-mode accent.
    final mode = ref.watch(
      dashboardBlocProvider.select((s) => s.snapshot.status.powerProfile),
    );
    final accent =
        LegionAccent.fromPowerModeValue(mode)?.color ??
        Theme.of(context).colorScheme.primary;
    // The sidebar pane reads a touch darker than the content, per the design.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sidebarColor = Color.alphaBlend(
      Colors.black.withValues(alpha: isDark ? 0.18 : 0.03),
      Theme.of(context).colorScheme.surface,
    );

    final width = MediaQuery.of(context).size.width;

    if (width < kYaruMasterDetailBreakpoint) {
      // Narrow layout — icons-only rail.
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
                title: Text(section.label, style: _titleStyle(context)),
                centerTitle: false,
                border: _titleBarBorder(context),
                actions: _titleBarActions(section),
              );
            },
          ),
        ),
        body: YaruNavigationPage(
          controller: _narrowController,
          itemBuilder: (context, index, selected) => YaruNavigationRailItem(
            icon: Icon(NavShellEntries.sections[index].yaruIcon),
            label: Text(NavShellEntries.sections[index].label),
            tooltip: NavShellEntries.sections[index].label,
            style: style,
          ),
          pageBuilder: (context, index) =>
              _buildPage(NavShellEntries.sections[index]),
          onSelected: (index) => _navigateTo(NavShellEntries.sections[index]),
        ),
      );
    }

    // Wide layout — flat sidebar with an accent-tinted active item.
    return YaruMasterDetailTheme(
      data: YaruMasterDetailTheme.of(
        context,
      ).copyWith(sideBarColor: sidebarColor),
      child: YaruMasterDetailPage(
        controller: _wideController,
        paneLayoutDelegate: const YaruResizablePaneDelegate(
          initialPaneSize: 280,
          minPageSize: kYaruMasterDetailBreakpoint / 2,
          minPaneSize: 175,
        ),
        tileBuilder: (context, index, selected, availableWidth) {
          final section = NavShellEntries.sections[index];
          return ListTileTheme(
            selectedColor: accent,
            selectedTileColor: accent.withValues(alpha: 0.18),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
            child: YaruMasterTile(
              leading: Icon(section.yaruIcon),
              title: Text(section.label),
            ),
          );
        },
        pageBuilder: (context, index) {
          final section = NavShellEntries.sections[index];
          return YaruDetailPage(
            appBar: YaruWindowTitleBar(
              border: _titleBarBorder(context),
              centerTitle: false,
              leading: Navigator.of(context).canPop()
                  ? const YaruBackButton()
                  : null,
              title: Text(section.label, style: _titleStyle(context)),
              actions: _titleBarActions(section),
            ),
            body: _buildPage(section),
          );
        },
        appBar: YaruWindowTitleBar(
          centerTitle: false,
          titleSpacing: 0,
          leading: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Center(child: LegionMark(color: accent, size: 22)),
          ),
          title: Text('Legion', style: _titleStyle(context)),
          border: _titleBarBorder(context),
          backgroundColor: sidebarColor,
        ),
        bottomBar: const _SidebarStatusFooter(),
        onSelected: (index) {
          if (index == null) return;
          _navigateTo(NavShellEntries.sections[index]);
        },
      ),
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
        return const BatteryPage();
      case AppSection.devices:
        return const DevicesPage();
      case AppSection.dgpu:
        return const DgpuPage();
      case AppSection.display:
        return const DisplayPage();
      case AppSection.lighting:
        return const LightingPage();
      case AppSection.automation:
        return const AutomationPage();
      case AppSection.settings:
        return const SettingsPage();
      case AppSection.diagnostics:
        return const DiagnosticsPage();
    }
  }
}

/// Sidebar footer: AC/charging status with the battery percentage, matching the
/// design. Watches power + battery state directly (page-level composition).
class _SidebarStatusFooter extends ConsumerWidget {
  const _SidebarStatusFooter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final onAc = ref.watch(
      dashboardBlocProvider.select((s) => s.snapshot.onPowerSupply),
    );
    final percent = ref.watch(
      batteryBlocProvider.select((s) => s.batteryPercent),
    );
    final charging = ref.watch(
      batteryBlocProvider.select((s) => s.batteryCharging),
    );

    final status = charging == true
        ? 'Charging'
        : onAc == true
        ? 'On AC power'
        : onAc == false
        ? 'On battery'
        : 'Power';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: scheme.onSurface.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        children: [
          Icon(
            charging == true
                ? YaruIcons.battery_full_charging
                : YaruIcons.battery,
            size: 18,
            color: scheme.onSurface.withValues(alpha: 0.6),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  status,
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (percent != null)
                  Text(
                    'Battery $percent%',
                    style: TextStyle(
                      fontFamily: kMonoFontFamily,
                      package: kMonoFontPackage,
                      fontSize: 11,
                      color: scheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
