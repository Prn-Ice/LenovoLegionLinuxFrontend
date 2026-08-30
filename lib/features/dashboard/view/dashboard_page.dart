import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../../core/theme/legion_accent.dart';
import '../../../core/widgets/app_shell_components.dart';
import '../../../core/widgets/privileged_action_notice.dart';
import '../bloc/dashboard_event.dart';
import '../models/dashboard_snapshot.dart';
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
import '../bloc/dashboard_state.dart';

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
    final snapshot = state.snapshot;
    final sensors = sensorState.snapshot;
    final accentObj = LegionAccent.fromPowerModeValue(
      snapshot.status.powerProfile?.trim(),
    );
    final accent = accentObj?.color ?? Theme.of(context).colorScheme.primary;
    final modeFacts = _modeFacts(
      cpuPackageWatts: sensors.cpuPackagePowerW,
      gpuWatts: sensors.gpuPowerDrawW,
    );

    return AppPageBody(
      errorMessage: state.errorMessage,
      noticeMessage: state.noticeMessage,
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
        _buildQuickControls(context, snapshot, state, devicesState, accent),
      ],
    );
  }

  Widget _buildQuickControls(
    BuildContext context,
    DashboardSnapshot snapshot,
    DashboardState state,
    DevicesState devicesState,
    Color accent,
  ) {
    final dashboardBloc = ref.read(dashboardBlocProvider.bloc);
    final devicesBloc = ref.read(devicesBlocProvider.bloc);

    ValueChanged<bool>? guard({
      required bool supported,
      required bool applying,
      required String title,
      required void Function(bool) apply,
    }) {
      if (!supported || applying) return null;
      return (enabled) async {
        final confirmed = await confirmPrivilegedAction(
          context,
          title: title,
          message:
              'This action uses privileged access and may require authentication.',
          confirmLabel: 'Apply',
        );
        if (!context.mounted || !confirmed) return;
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
          value: snapshot.rapidChargingEnabled ?? false,
          onChanged: guard(
            supported: snapshot.rapidChargingEnabled != null,
            applying: state.isApplying,
            title: 'Set rapid charging',
            apply: (v) =>
                dashboardBloc.add(DashboardRapidChargingSetRequested(v)),
          ),
        ),
        QuickControl(
          icon: YaruIcons.health,
          title: 'Battery health',
          subtitle: 'Stop charging near 80% to extend lifespan',
          value: snapshot.batteryConservationEnabled ?? false,
          onChanged: guard(
            supported: snapshot.batteryConservationEnabled != null,
            applying: state.isApplying,
            title: 'Set battery conservation',
            apply: (v) =>
                dashboardBloc.add(DashboardBatteryConservationSetRequested(v)),
          ),
        ),
        QuickControl(
          icon: YaruIcons.keyboard,
          title: 'Fn lock',
          subtitle: 'F-keys act as F1–F12 directly',
          value: devicesState.fnLockEnabled ?? false,
          onChanged: guard(
            supported: devicesState.fnLockSupported,
            applying: devicesState.isApplying,
            title: 'Set Fn lock',
            apply: (v) => devicesBloc.add(FnLockSetRequested(v)),
          ),
        ),
        QuickControl(
          icon: YaruIcons.touchpad,
          title: 'Touchpad',
          subtitle: 'Tap and click enabled',
          value: devicesState.touchpadEnabled ?? false,
          onChanged: guard(
            supported: devicesState.touchpadSupported,
            applying: devicesState.isApplying,
            title: 'Set touchpad',
            apply: (v) => devicesBloc.add(TouchpadSetRequested(v)),
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
