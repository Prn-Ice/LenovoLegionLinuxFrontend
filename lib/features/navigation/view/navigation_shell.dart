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

    void onSelectedNullable(int? index) {
      if (index != null) onSelected(index);
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
      onSelected: onSelectedNullable,
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
