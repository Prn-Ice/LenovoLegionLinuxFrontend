import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../../core/widgets/legion_mark.dart';
import '../../../core/widgets/metric_format.dart';
import '../../../core/widgets/app_shell_components.dart';
import '../../automation/providers/automation_runtime_provider.dart';
import '../../automation/providers/automation_provider.dart';
import '../../lighting/providers/lighting_provider.dart';
import '../../lighting/bloc/rgb_lighting_event.dart';
import '../../automation/view/automation_page.dart';
import '../../battery/bloc/battery_state.dart';
import '../../battery/bloc/battery_event.dart';
import '../../battery/providers/battery_provider.dart';
import '../../battery/view/battery_page.dart';
import '../../dashboard/bloc/dashboard_event.dart';
import '../../dashboard/providers/dashboard_provider.dart';
import '../../dashboard/view/dashboard_page.dart';
import '../../about/bloc/about_event.dart';
import '../../about/providers/about_provider.dart';
import '../../boot_logo/bloc/boot_logo_event.dart';
import '../../boot_logo/providers/boot_logo_provider.dart';
import '../../devices/bloc/devices_event.dart';
import '../../devices/providers/devices_provider.dart';
import '../../display/bloc/display_event.dart';
import '../../display/providers/display_provider.dart';
import '../../dgpu/bloc/dgpu_event.dart';
import '../../dgpu/providers/dgpu_provider.dart';
import '../../dgpu/view/dgpu_page.dart';
import '../../fans/view/fans_page.dart';
import '../../lighting/view/lighting_page.dart';
import '../../power/bloc/power_event.dart';
import '../../power/providers/power_provider.dart';
import '../../power/view/power_page.dart';
import '../../settings/bloc/settings_event.dart';
import '../../settings/providers/settings_provider.dart';
import '../../settings/view/settings_page.dart';
import '../bloc/navigation_event.dart';
import '../models/app_section.dart';
import '../models/nav_entry.dart';
import '../models/settings_refresh_targets.dart';
import '../providers/navigation_provider.dart';

const _pageColor = Color(0xffFAF9F8);

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
    if (section == AppSection.settings) {
      final settings = ref.watch(settingsBlocProvider);
      final bootLogo = ref.watch(bootLogoBlocProvider);
      final about = ref.watch(aboutBlocProvider);
      final devices = ref.watch(devicesBlocProvider);
      final display = ref.watch(displayBlocProvider);
      final refreshTargets = SettingsRefreshTargets.fromBusyStates(
        settingsLoading: settings.isLoading,
        settingsApplying: settings.isApplying,
        bootLogoLoading: bootLogo.isLoading,
        bootLogoApplying: bootLogo.isApplying,
        aboutLoading: about.isLoading,
        devicesLoading: devices.isLoading,
        devicesApplying: devices.isApplying,
        displayLoading: display.isLoading,
        displayApplying: display.isApplying,
      );

      return [
        IconButton(
          icon: const Icon(YaruIcons.refresh, size: 18),
          tooltip: 'Refresh',
          onPressed: refreshTargets.canRefresh
              ? () {
                  if (refreshTargets.settings) {
                    ref
                        .read(settingsBlocProvider.bloc)
                        .add(const SettingsRefreshRequested());
                  }
                  if (refreshTargets.bootLogo) {
                    ref
                        .read(bootLogoBlocProvider.bloc)
                        .add(const BootLogoRefreshRequested());
                  }
                  if (refreshTargets.about) {
                    ref
                        .read(aboutBlocProvider.bloc)
                        .add(const AboutRefreshRequested());
                  }
                  if (refreshTargets.devices) {
                    ref
                        .read(devicesBlocProvider.bloc)
                        .add(const DevicesRefreshRequested());
                  }
                  if (refreshTargets.display) {
                    ref
                        .read(displayBlocProvider.bloc)
                        .add(const DisplayRefreshRequested());
                  }
                }
              : null,
        ),
      ];
    }

    final VoidCallback? onRefresh = switch (section) {
      AppSection.dashboard => () {
        ref
            .read(dashboardBlocProvider.bloc)
            .add(const DashboardRefreshRequested());
        ref.read(batteryBlocProvider.bloc).add(const BatteryRefreshRequested());
      },
      AppSection.power => () {
        ref.read(powerBlocProvider.bloc).add(const PowerRefreshRequested());
        ref.read(batteryBlocProvider.bloc).add(const BatteryRefreshRequested());
      },
      AppSection.battery =>
        () => ref
            .read(batteryBlocProvider.bloc)
            .add(const BatteryRefreshRequested()),
      AppSection.dgpu =>
        () => ref.read(dgpuBlocProvider.bloc).add(const DgpuRefreshRequested()),
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
    ref.watch(automationRuntimeProvider);
    final keyboardError =
        ref.watch(automationBlocProvider).config.profiles.isNotEmpty
        ? ref.watch(
            rgbLightingBlocProvider.select((state) => state.visibleErrorMessage),
          )
        : null;
    // Keep controllers in sync with the navigation bloc.
    ref.listen(navigationBlocProvider, (prev, next) {
      if (prev?.section == next.section) return;
      final idx = NavShellEntries.indexFor(next.section);
      if (_wideController.index != idx) _wideController.index = idx;
      if (_narrowController.index != idx) _narrowController.index = idx;
    });

    return AppErrorDialogListener(
      errorMessage: switch (ref.watch(navigationBlocProvider).section) {
        AppSection.lighting || AppSection.automation => null,
        _ => keyboardError,
      },
      onErrorDismissed: (error) =>
          ref.read(rgbLightingBlocProvider.bloc).add(RgbErrorDismissed(error)),
      child: _buildLayout(context),
    );
  }

  Widget _buildLayout(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    // The sidebar pane reads a touch darker than the content, per the design.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sidebarColor = isDark
        ? Color.alphaBlend(
            Colors.black.withValues(alpha: 0.18),
            Theme.of(context).colorScheme.surface,
          )
        : const Color(0xffECEBE9);

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
            icon: IconTheme.merge(
              data: IconThemeData(color: selected ? accent : null),
              child: NavShellEntries.sections[index].icon,
            ),
            label: Text(NavShellEntries.sections[index].label),
            tooltip: NavShellEntries.sections[index].label,
            style: style,
          ),
          pageBuilder: (context, index) => ColoredBox(
            color: isDark ? Theme.of(context).colorScheme.surface : _pageColor,
            child: _buildPage(NavShellEntries.sections[index]),
          ),
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
              leading: section.icon,
              title: Text(section.label),
            ),
          );
        },
        pageBuilder: (context, index) {
          final section = NavShellEntries.sections[index];
          return YaruDetailPage(
            backgroundColor: isDark ? null : _pageColor,
            appBar: YaruWindowTitleBar(
              border: _titleBarBorder(context),
              centerTitle: false,
              leading: Navigator.of(context).canPop()
                  ? const YaruBackButton()
                  : null,
              title: Text(section.label, style: _titleStyle(context)),
              actions: _titleBarActions(section),
              backgroundColor: isDark ? null : _pageColor,
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

  Widget _buildPage(AppSection section) => switch (section) {
    AppSection.dashboard => const DashboardPage(),
    AppSection.power => const PowerPage(),
    AppSection.fans => const FansPage(),
    AppSection.battery => const BatteryPage(),
    AppSection.lighting => const LightingPage(),
    AppSection.dgpu => const DgpuPage(),
    AppSection.automation => const AutomationPage(),
    AppSection.settings => SettingsPage(),
  };
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
    final batteryState = ref.watch(batteryBlocProvider);
    final percent = batteryState.batteryPercent;
    final charging = batteryState.batteryCharging;
    final estimate = batteryState.estimatedTimeMinutes(onPowerSupply: onAc);
    final known = percent != null || charging != null || onAc != null;

    final status = charging == true
        ? 'Charging'
        : onAc == true
        ? 'On AC power'
        : onAc == false
        ? 'On battery'
        : 'Power';

    final detail = percent == null
        ? null
        : estimate == null
        ? 'Battery $percent%'
        : '$percent% · ${formatBatteryDuration(estimate)} '
              '${charging == true ? 'to full' : 'left'}';

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
            color: known
                ? const Color(0xff3A9D4F)
                : scheme.onSurface.withValues(alpha: 0.6),
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
                if (detail != null)
                  Text(
                    detail,
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
