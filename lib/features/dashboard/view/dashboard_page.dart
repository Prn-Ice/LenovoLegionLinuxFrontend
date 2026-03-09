import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../../core/widgets/app_shell_components.dart';
import '../../../core/widgets/privileged_action_notice.dart';
import '../bloc/dashboard_event.dart';
import '../models/dashboard_snapshot.dart';
import '../providers/dashboard_provider.dart';
import '../../sensors/models/live_sensor_snapshot.dart';
import '../widgets/device_identity_card.dart';
import '../widgets/sensor_strip.dart';
import '../../navigation/bloc/navigation_event.dart';
import '../../navigation/models/app_section.dart';
import '../../navigation/providers/navigation_provider.dart';
import '../../sensors/bloc/live_sensor_event.dart';
import '../../sensors/providers/live_sensor_provider.dart';
import '../bloc/dashboard_state.dart';

class DashboardPage extends ConsumerStatefulWidget {
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
      sections: [AppSection.battery, AppSection.display],
    ),
    _SectionGroup(
      title: 'Automation & System',
      description:
          'Rules, service management, and diagnostics for troubleshooting.',
      sections: [AppSection.automation, AppSection.settings, AppSection.diagnostics],
    ),
  ];

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(liveSensorBlocProvider.bloc).add(const LiveSensorStarted());
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dashboardBlocProvider);
    final sensorState = ref.watch(liveSensorBlocProvider);
    final snapshot = state.snapshot;
    final sensors = sensorState.snapshot;

    return AppPageBody(
      title: 'Legion Control Center',
      subtitle: _buildStatusLine(context, snapshot, sensors),
      errorMessage: state.errorMessage,
      noticeMessage: state.noticeMessage,
      children: [
        DeviceIdentityCard(identity: snapshot.deviceIdentity),
        const SizedBox(height: 16),
        SensorStrip(snapshot: sensors),
        const SizedBox(height: 16),
        _buildControlCards(context, snapshot, state),
        const SizedBox(height: 16),
        ..._buildSectionGroups(context),
        const SizedBox(height: 16),
        AppRefreshButton(
          isBusy: state.isLoading,
          onPressed: state.isApplying
              ? null
              : () => ref
                    .read(dashboardBlocProvider.bloc)
                    .add(const DashboardRefreshRequested()),
        ),
      ],
    );
  }

  Widget _buildControlCards(
    BuildContext context,
    DashboardSnapshot snapshot,
    DashboardState state,
  ) {
    final bloc = ref.read(dashboardBlocProvider.bloc);
    final navigationBloc = ref.read(navigationBlocProvider.bloc);

    final cardWidth = _cardWidth(context);
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        // Power Mode card
        SizedBox(
          width: cardWidth,
          child: DashboardCard(
            icon: Icons.bolt,
            title: 'Power Mode',
            tint: Theme.of(context).colorScheme.primary,
            children: [
              Text(
                snapshot.status.powerProfileLabel,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
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
              const SizedBox(height: 12),
              Text(
                'Power source: ${_powerSourceLabel(snapshot.onPowerSupply)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                'Context fan preset: ${snapshot.recommendedFanPreset ?? 'Unavailable'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              if (snapshot.availablePowerModes.isEmpty)
                const Text('No writable power modes available.')
              else
                YaruChoiceChipBar(
                  labels: snapshot.availablePowerModes
                      .map((mode) => Text(mode))
                      .toList(growable: false),
                  isSelected: snapshot.availablePowerModes
                      .map(
                        (mode) =>
                            snapshot.status.powerProfile?.trim() == mode,
                      )
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
              const SizedBox(height: 12),
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
                        child: YaruCircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.tune),
                label: const Text('Apply context fan preset'),
              ),
            ],
          ),
        ),

        // Graphics Mode card
        SizedBox(
          width: cardWidth,
          child: DashboardCard(
            icon: Icons.display_settings,
            title: 'Graphics Mode',
            children: [
              const PrivilegedActionNotice(),
              const SizedBox(height: 8),
              AppSwitchTile(
                value: snapshot.hybridModeEnabled ?? false,
                onChanged:
                    snapshot.hybridModeEnabled != null && !state.isApplying
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
              AppSwitchTile(
                value: snapshot.overdriveEnabled ?? false,
                onChanged:
                    snapshot.overdriveEnabled != null && !state.isApplying
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
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    navigationBloc.add(
                      const NavigationSectionSelected(AppSection.display),
                    );
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open Display & Lighting'),
                ),
              ),
            ],
          ),
        ),

        // Battery card
        SizedBox(
          width: cardWidth,
          child: DashboardCard(
            icon: Icons.battery_charging_full,
            title: 'Battery',
            children: [
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
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildSectionGroups(BuildContext context) {
    final navigationBloc = ref.read(navigationBlocProvider.bloc);
    return DashboardPage._sectionGroups
        .map(
          (group) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _SectionGroupCard(
              group: group,
              onSectionTap: (section) {
                navigationBloc.add(NavigationSectionSelected(section));
              },
            ),
          ),
        )
        .toList();
  }

  Widget _buildStatusLine(
    BuildContext context,
    DashboardSnapshot snapshot,
    LiveSensorSnapshot sensors,
  ) {
    final parts = <String>[];

    final mode = snapshot.status.powerProfile?.trim() ?? '';
    if (mode.isNotEmpty) parts.add(mode);

    if (snapshot.hybridModeEnabled == true) {
      parts.add('Hybrid');
    } else if (snapshot.hybridModeEnabled == false) {
      parts.add('Discrete');
    }

    if (sensors.cpuTempC != null) {
      parts.add('${sensors.cpuTempC!.toStringAsFixed(0)}°C');
    }

    if (snapshot.onPowerSupply == true) {
      parts.add('AC');
    } else if (snapshot.onPowerSupply == false) {
      parts.add('Battery');
    }

    if (parts.isEmpty) return const SizedBox.shrink();

    return Text(
      parts.join('  ·  '),
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
      ),
    );
  }

  double _cardWidth(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width > 900) return (width - 280 - 48) / 2;
    return width - 32;
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
    return YaruExpandable(
      isExpanded: true,
      expandButtonPosition: YaruExpandableButtonPosition.end,
      header: Text(group.title, style: Theme.of(context).textTheme.titleMedium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              group.description,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          ...group.sections.map(
            (section) => InkWell(
              onTap: () => onSectionTap(section),
              borderRadius: BorderRadius.circular(8),
              child: YaruTile(
                leading: Icon(section.icon),
                title: Text(section.label),
                trailing: const Icon(Icons.chevron_right),
                enabled: true,
              ),
            ),
          ),
        ],
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
