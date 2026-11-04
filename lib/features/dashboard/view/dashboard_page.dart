import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../../core/widgets/app_shell_components.dart';
import '../../../core/widgets/privileged_action_notice.dart';
import '../bloc/dashboard_event.dart';
import '../../battery/bloc/battery_event.dart';
import '../../battery/bloc/battery_state.dart';
import '../../battery/providers/battery_provider.dart';
import '../providers/dashboard_provider.dart';
import '../widgets/device_identity_card.dart';
import '../widgets/mode_hero.dart';
import '../widgets/quick_controls.dart';
import '../widgets/sensor_strip.dart';
import '../../devices/bloc/devices_event.dart';
import '../../devices/bloc/devices_state.dart';
import '../../devices/providers/devices_provider.dart';
import '../../sensors/bloc/live_sensor_event.dart';
import '../../sensors/providers/live_sensor_provider.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

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
    final devicesState = ref.watch(devicesBlocProvider);
    final batteryState = ref.watch(batteryBlocProvider);
    final snapshot = state.snapshot;
    final sensors = sensorState.snapshot;

    if (!state.hasInitialized || sensorState.isLoading) {
      return Semantics(
        label: 'Loading dashboard data',
        child: const Center(child: YaruCircularProgressIndicator()),
      );
    }

    final accent = Theme.of(context).colorScheme.primary;
    final modeFacts = _modeFacts(
      cpuPackageWatts: sensors.cpuPackagePowerW,
      gpuWatts: sensors.gpuPowerDrawW,
    );

    return AppPageBody(
      errorMessage:
          state.errorMessage ??
          batteryState.errorMessage ??
          devicesState.errorMessage ??
          sensorState.errorMessage,
      children: [
        ModeHero(
          accent: accent,
          facts: modeFacts,
          availableModes: snapshot.availablePowerModes,
          selectedMode: snapshot.status.powerProfile,
          isApplying: state.isApplying,
          onModeSelected: state.isApplying
              ? null
              : (index) {
                  final mode = snapshot.availablePowerModes[index];
                  ref
                      .read(dashboardBlocProvider.bloc)
                      .add(DashboardPowerModeSetRequested(mode));
                },
        ),
        const SizedBox(height: 16),
        DeviceIdentityCard(identity: snapshot.deviceIdentity, accent: accent),
        const SizedBox(height: 16),
        SensorStrip(snapshot: sensors, accent: accent),
        const SizedBox(height: 16),
        _buildQuickControls(context, batteryState, devicesState, accent),
      ],
    );
  }

  Widget _buildQuickControls(
    BuildContext context,
    BatteryState batteryState,
    DevicesState devicesState,
    Color accent,
  ) {
    ValueChanged<bool>? guard({
      required bool Function() canApply,
      required String title,
      required void Function(bool) apply,
    }) {
      if (!canApply()) return null;
      return (enabled) async {
        final confirmed = await confirmPrivilegedAction(
          context,
          title: title,
          message:
              'This action uses privileged access and may require authentication.',
          confirmLabel: 'Apply',
        );
        if (!context.mounted || !confirmed || !canApply()) return;
        apply(enabled);
      };
    }

    return QuickControls(
      accent: accent,
      controls: [
        QuickControl(
          icon: YaruIcons.thunderbolt,
          title: 'Rapid charge',
          subtitle: 'Charge to full as fast as possible',
          value: batteryState.rapidChargingEnabled ?? false,
          onChanged: guard(
            canApply: () {
              final current = ref.read(batteryBlocProvider);
              return current.rapidChargingSupported && !current.isApplying;
            },
            title: 'Set rapid charging',
            apply: (v) => ref
                .read(batteryBlocProvider.bloc)
                .add(RapidChargingSetRequested(v)),
          ),
        ),
        QuickControl(
          icon: YaruIcons.health,
          title: 'Battery health',
          subtitle: 'Stop charging near 80% to extend lifespan',
          value: batteryState.batteryConservationEnabled ?? false,
          onChanged: guard(
            canApply: () {
              final current = ref.read(batteryBlocProvider);
              return current.batteryConservationSupported &&
                  !current.isApplying;
            },
            title: 'Set battery conservation',
            apply: (v) => ref
                .read(batteryBlocProvider.bloc)
                .add(BatteryConservationSetRequested(v)),
          ),
        ),
        QuickControl(
          icon: YaruIcons.keyboard,
          title: 'Fn lock',
          subtitle: 'F-keys act as F1–F12 directly',
          value: devicesState.fnLockEnabled ?? false,
          onChanged: guard(
            canApply: () {
              final current = ref.read(devicesBlocProvider);
              return current.fnLockSupported && !current.isApplying;
            },
            title: 'Set Fn lock',
            apply: (v) =>
                ref.read(devicesBlocProvider.bloc).add(FnLockSetRequested(v)),
          ),
        ),
        QuickControl(
          icon: YaruIcons.touchpad,
          title: 'Touchpad',
          subtitle: 'Tap and click enabled',
          value: devicesState.touchpadEnabled ?? false,
          onChanged: guard(
            canApply: () {
              final current = ref.read(devicesBlocProvider);
              return current.touchpadSupported && !current.isApplying;
            },
            title: 'Set touchpad',
            apply: (v) =>
                ref.read(devicesBlocProvider.bloc).add(TouchpadSetRequested(v)),
          ),
        ),
      ],
    );
  }

  String? _modeFacts({double? cpuPackageWatts, double? gpuWatts}) {
    final parts = <String>[];
    if (cpuPackageWatts != null) {
      parts.add('CPU package ${cpuPackageWatts.toStringAsFixed(1)} W');
    }
    if (gpuWatts != null) {
      parts.add('GPU ${gpuWatts.toStringAsFixed(1)} W');
    }
    return parts.isEmpty ? null : parts.join('  ·  ');
  }
}
