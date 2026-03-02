import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

class NavigationShell extends ConsumerWidget {
  const NavigationShell({super.key});

  static const List<AppSection> _sections = AppSection.values;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(navigationBlocProvider);
    final bloc = ref.read(navigationBlocProvider.bloc);
    final theme = Theme.of(context);
    final width = MediaQuery.of(context).size.width;
    final isCompact = width < 960;

    if (isCompact) {
      return Scaffold(
        body: SafeArea(child: _buildPage(state.section)),
        bottomNavigationBar: NavigationBar(
          selectedIndex: state.section.index,
          destinations: _sections
              .map(
                (section) => NavigationDestination(
                  icon: Icon(section.icon),
                  label: section.label,
                ),
              )
              .toList(growable: false),
          onDestinationSelected: (value) {
            bloc.add(NavigationSectionSelected(_sections[value]));
          },
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            NavigationRail(
              backgroundColor: theme.colorScheme.surfaceContainerLowest,
              selectedIndex: state.section.index,
              onDestinationSelected: (value) {
                bloc.add(NavigationSectionSelected(_sections[value]));
              },
              labelType: NavigationRailLabelType.all,
              destinations: _sections
                  .map(
                    (section) => NavigationRailDestination(
                      icon: Icon(section.icon),
                      label: Text(section.label),
                    ),
                  )
                  .toList(growable: false),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: _buildPage(state.section)),
          ],
        ),
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
