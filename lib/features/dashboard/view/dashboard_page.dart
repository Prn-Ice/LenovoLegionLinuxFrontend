import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/legion_accent.dart';
import '../../../core/widgets/app_shell_components.dart';
import '../../../core/widgets/privileged_action_notice.dart';
import '../bloc/dashboard_event.dart';
import '../models/dashboard_snapshot.dart';
import '../providers/dashboard_provider.dart';
import '../../sensors/models/live_sensor_snapshot.dart';
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

    return AppPageBody(
      title: 'Legion Control Center',
      subtitle: _buildStatusLine(context, snapshot, sensors),
      errorMessage: state.errorMessage,
      noticeMessage: state.noticeMessage,
      children: [
        ModeHero(
          accent: accent,
          availableModes: snapshot.availablePowerModes,
          selectedMode: snapshot.status.powerProfile,
          isApplying: state.isApplying,
          onModeSelected: state.isApplying
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
                  ref
                      .read(dashboardBlocProvider.bloc)
                      .add(DashboardPowerModeSetRequested(mode));
                },
        ),
        const SizedBox(height: 16),
        DeviceIdentityCard(identity: snapshot.deviceIdentity),
        const SizedBox(height: 16),
        SensorStrip(snapshot: sensors, accent: accent),
        const SizedBox(height: 16),
        _buildQuickControls(context, snapshot, state, devicesState, accent),
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
          icon: Icons.bolt,
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
          icon: Icons.health_and_safety_outlined,
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
          icon: Icons.keyboard_outlined,
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
          icon: Icons.touch_app_outlined,
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

  Widget _buildStatusLine(
    BuildContext context,
    DashboardSnapshot snapshot,
    LiveSensorSnapshot sensors,
  ) {
    final parts = <String>[];

    final mode = snapshot.status.powerProfile?.trim() ?? '';
    if (mode.isNotEmpty) parts.add(humanizeMode(mode));

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
}
