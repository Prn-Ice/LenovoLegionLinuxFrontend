import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_shell_components.dart';
import '../../../core/widgets/privileged_action_notice.dart';
import '../bloc/dashboard_event.dart';
import '../providers/dashboard_provider.dart';
import '../../navigation/bloc/navigation_event.dart';
import '../../navigation/models/app_section.dart';
import '../../navigation/providers/navigation_provider.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  static const List<_SectionGroup> _sectionGroups = [
    _SectionGroup(
      title: 'Power & Performance',
      description:
          'Core controls for performance mode, fan behavior, and power limits.',
      sections: [AppSection.power, AppSection.fans],
    ),
    _SectionGroup(
      title: 'Devices & Display',
      description:
          'Battery protections, device toggles, hybrid mode, and display tuning.',
      sections: [AppSection.battery, AppSection.displayLighting],
    ),
    _SectionGroup(
      title: 'Automation & System',
      description:
          'Rules, service management, and diagnostics for troubleshooting.',
      sections: [AppSection.automation, AppSection.settings, AppSection.about],
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dashboardBlocProvider);
    final bloc = ref.read(dashboardBlocProvider.bloc);
    final navigationBloc = ref.read(navigationBlocProvider.bloc);
    final snapshot = state.snapshot;

    return AppPageBody(
      title: 'Dashboard',
      errorMessage: state.errorMessage,
      noticeMessage: state.noticeMessage,
      children: [
        AppSectionCard(
          title: 'Power Profile',
          children: [
            Text(
              snapshot.status.powerProfileLabel,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Updated: ${snapshot.status.updatedAt.toLocal()}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (snapshot.status.hasError) ...[
              const SizedBox(height: 8),
              AppStatusBanner(
                message: snapshot.status.error!,
                tone: AppStatusTone.error,
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        AppSectionCard(
          title: 'Quick Actions',
          children: [
            const PrivilegedActionNotice(),
            const SizedBox(height: 8),
            Text('Power source: ${_powerSourceLabel(snapshot.onPowerSupply)}'),
            Text(
              'Context fan preset: ${snapshot.recommendedFanPreset ?? 'Unavailable'}',
            ),
            const SizedBox(height: 12),
            Text(
              'Set power mode',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
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
            const SizedBox(height: 12),
            AppSwitchTile(
              value: snapshot.hybridModeEnabled ?? false,
              onChanged: snapshot.hybridModeEnabled != null && !state.isApplying
                  ? (enabled) async {
                      final confirmed = await confirmPrivilegedAction(
                        context,
                        title: 'Toggle hybrid mode',
                        message:
                            'This action uses privileged access and may require authentication.',
                        confirmLabel: 'Apply',
                      );
                      if (!context.mounted || !confirmed) {
                        return;
                      }
                      bloc.add(DashboardHybridModeSetRequested(enabled));
                    }
                  : null,
              title: 'Hybrid mode',
              subtitle: boolEnabledLabel(snapshot.hybridModeEnabled),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  navigationBloc.add(
                    const NavigationSectionSelected(AppSection.displayLighting),
                  );
                },
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open Display & Lighting'),
              ),
            ),
            AppSwitchTile(
              value: snapshot.overdriveEnabled ?? false,
              onChanged: snapshot.overdriveEnabled != null && !state.isApplying
                  ? (enabled) async {
                      final confirmed = await confirmPrivilegedAction(
                        context,
                        title: 'Toggle overdrive',
                        message:
                            'This action uses privileged access and may require authentication.',
                        confirmLabel: 'Apply',
                      );
                      if (!context.mounted || !confirmed) {
                        return;
                      }
                      bloc.add(DashboardOverdriveModeSetRequested(enabled));
                    }
                  : null,
              title: 'Overdrive',
              subtitle: boolEnabledLabel(snapshot.overdriveEnabled),
            ),
            const SizedBox(height: 8),
            AppSwitchTile(
              value: snapshot.batteryConservationEnabled ?? false,
              onChanged:
                  snapshot.batteryConservationEnabled != null &&
                      !state.isApplying
                  ? (enabled) async {
                      final confirmed = await confirmPrivilegedAction(
                        context,
                        title: 'Set battery conservation',
                        message:
                            'This action uses privileged access and may require authentication.',
                        confirmLabel: 'Apply',
                      );
                      if (!context.mounted || !confirmed) {
                        return;
                      }
                      bloc.add(
                        DashboardBatteryConservationSetRequested(enabled),
                      );
                    }
                  : null,
              title: 'Battery conservation',
              subtitle: boolEnabledLabel(snapshot.batteryConservationEnabled),
            ),
            AppSwitchTile(
              value: snapshot.rapidChargingEnabled ?? false,
              onChanged:
                  snapshot.rapidChargingEnabled != null && !state.isApplying
                  ? (enabled) async {
                      final confirmed = await confirmPrivilegedAction(
                        context,
                        title: 'Set rapid charging',
                        message:
                            'This action uses privileged access and may require authentication.',
                        confirmLabel: 'Apply',
                      );
                      if (!context.mounted || !confirmed) {
                        return;
                      }
                      bloc.add(DashboardRapidChargingSetRequested(enabled));
                    }
                  : null,
              title: 'Rapid charging',
              subtitle: boolEnabledLabel(snapshot.rapidChargingEnabled),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  navigationBloc.add(
                    const NavigationSectionSelected(AppSection.battery),
                  );
                },
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open Battery & Devices'),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: state.isApplying
                  ? null
                  : () async {
                      final confirmed = await confirmPrivilegedAction(
                        context,
                        title: 'Apply context fan preset',
                        message:
                            'Applying fan presets writes hardware controls and may prompt for authentication.',
                        confirmLabel: 'Apply preset',
                      );
                      if (!context.mounted || !confirmed) {
                        return;
                      }
                      bloc.add(const DashboardApplyContextFanPresetRequested());
                    },
              icon: state.isApplying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.tune),
              label: const Text('Apply context fan preset'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ..._sectionGroups.map(
          (group) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _SectionGroupCard(
              group: group,
              onSectionTap: (section) {
                navigationBloc.add(NavigationSectionSelected(section));
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        AppRefreshButton(
          isBusy: state.isLoading,
          onPressed: state.isApplying
              ? null
              : () => bloc.add(const DashboardRefreshRequested()),
        ),
      ],
    );
  }

  String _powerSourceLabel(bool? onPowerSupply) {
    if (onPowerSupply == null) {
      return 'Unknown';
    }
    return onPowerSupply ? 'AC' : 'Battery';
  }
}

class _SectionGroupCard extends StatelessWidget {
  const _SectionGroupCard({required this.group, required this.onSectionTap});

  final _SectionGroup group;
  final ValueChanged<AppSection> onSectionTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(group.title, style: textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(group.description),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: group.sections
                  .map(
                    (section) => OutlinedButton.icon(
                      onPressed: () => onSectionTap(section),
                      icon: Icon(section.icon),
                      label: Text('Open ${section.label}'),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionGroup {
  const _SectionGroup({
    required this.title,
    required this.description,
    required this.sections,
  });

  final String title;
  final String description;
  final List<AppSection> sections;
}
