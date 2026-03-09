import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../about/view/about_page.dart';
import '../../automation/view/automation_page.dart';
import '../../battery_devices/view/battery_devices_page.dart';
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
      // TODO(Task 14): replace with BatteryPage when BatteryBloc is split
      case AppSection.battery:
        return const BatteryDevicesPage();
      // TODO(Task 15): replace with DevicesPage when BatteryBloc is split
      case AppSection.devices:
        return const BatteryDevicesPage();
      case AppSection.dgpu:
        return const DgpuPage();
      // TODO(Task 12): replace with DisplayPage when DisplayLightingBloc is split
      case AppSection.display:
        return const DisplayLightingPage();
      // TODO(Task 13): replace with LightingPage when DisplayLightingBloc is split
      case AppSection.lighting:
        return const DisplayLightingPage();
      case AppSection.automation:
        return const AutomationPage();
      case AppSection.settings:
        return const SettingsPage();
      // TODO(Task 21): replace with DiagnosticsPage when diagnostics page is implemented
      case AppSection.diagnostics:
        return const AboutPage();
    }
  }
}
