import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_shell_components.dart';
import '../../../core/widgets/privileged_action_notice.dart';
import '../bloc/battery_devices_event.dart';
import '../bloc/battery_devices_state.dart';
import '../providers/battery_devices_provider.dart';

class BatteryDevicesPage extends ConsumerWidget {
  const BatteryDevicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(batteryDevicesBlocProvider);
    final bloc = ref.read(batteryDevicesBlocProvider.bloc);

    if (state.isLoading && !state.hasLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    return AppPageBody(
      title: 'Battery & Devices',
      errorMessage: state.errorMessage,
      noticeMessage: state.noticeMessage,
      children: [
        AppSectionCard(
          title: 'Battery',
          children: [
            const PrivilegedActionNotice(),
            const SizedBox(height: 8),
            AppSwitchTile(
              value: state.batteryConservationEnabled ?? false,
              onChanged:
                  _isWritable(
                    state.batteryConservationEnabled,
                    state.isApplying,
                  )
                  ? (enabled) async {
                      final confirmed = await confirmPrivilegedAction(
                        context,
                        title: 'Set battery conservation',
                        message:
                            'This action uses privileged access and may prompt for authentication.',
                        confirmLabel: 'Apply',
                      );
                      if (!context.mounted || !confirmed) {
                        return;
                      }
                      bloc.add(BatteryConservationSetRequested(enabled));
                    }
                  : null,
              title: 'Battery conservation',
              subtitle: boolEnabledLabel(state.batteryConservationEnabled),
            ),
            AppSwitchTile(
              value: state.rapidChargingEnabled ?? false,
              onChanged:
                  _isWritable(state.rapidChargingEnabled, state.isApplying)
                  ? (enabled) async {
                      final confirmed = await confirmPrivilegedAction(
                        context,
                        title: 'Set rapid charging',
                        message:
                            'This action uses privileged access and may prompt for authentication.',
                        confirmLabel: 'Apply',
                      );
                      if (!context.mounted || !confirmed) {
                        return;
                      }
                      bloc.add(RapidChargingSetRequested(enabled));
                    }
                  : null,
              title: 'Rapid charging',
              subtitle: boolEnabledLabel(state.rapidChargingEnabled),
            ),
            AppSwitchTile(
              value: state.alwaysOnUsbChargingEnabled ?? false,
              onChanged: _alwaysOnUsbWritable(state)
                  ? (enabled) async {
                      final confirmed = await confirmPrivilegedAction(
                        context,
                        title: 'Set always-on USB charging',
                        message:
                            'This keeps USB charging active when the laptop is off. The action uses privileged access and may prompt for authentication.',
                        confirmLabel: 'Apply',
                      );
                      if (!context.mounted || !confirmed) {
                        return;
                      }
                      bloc.add(AlwaysOnUsbChargingSetRequested(enabled));
                    }
                  : null,
              title: 'Always-on USB charging',
              subtitle: _alwaysOnUsbSubtitle(state),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppSectionCard(
          title: 'Input Devices',
          children: [
            const PrivilegedActionNotice(),
            const SizedBox(height: 8),
            AppSwitchTile(
              value: state.touchpadEnabled ?? false,
              onChanged: _isWritable(state.touchpadEnabled, state.isApplying)
                  ? (enabled) async {
                      final confirmed = await confirmPrivilegedAction(
                        context,
                        title: 'Set touchpad state',
                        message:
                            'This action uses privileged access and may prompt for authentication.',
                        confirmLabel: 'Apply',
                      );
                      if (!context.mounted || !confirmed) {
                        return;
                      }
                      bloc.add(TouchpadSetRequested(enabled));
                    }
                  : null,
              title: 'Touchpad',
              subtitle: boolEnabledLabel(state.touchpadEnabled),
            ),
            AppSwitchTile(
              value: state.winKeyEnabled ?? false,
              onChanged: _isWritable(state.winKeyEnabled, state.isApplying)
                  ? (enabled) async {
                      final confirmed = await confirmPrivilegedAction(
                        context,
                        title: 'Set Win key lock',
                        message:
                            'This action uses privileged access and may prompt for authentication.',
                        confirmLabel: 'Apply',
                      );
                      if (!context.mounted || !confirmed) {
                        return;
                      }
                      bloc.add(WinKeySetRequested(enabled));
                    }
                  : null,
              title: 'Win key',
              subtitle: boolEnabledLabel(state.winKeyEnabled),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Camera power'),
              subtitle: Text(
                state.cameraPowerEnabled == null
                    ? 'Unavailable on this device'
                    : '${boolEnabledLabel(state.cameraPowerEnabled)} (read-only)',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppRefreshButton(
          isBusy: state.isLoading,
          onPressed: state.isApplying
              ? null
              : () => bloc.add(const BatteryDevicesRefreshRequested()),
        ),
      ],
    );
  }

  bool _isWritable(bool? value, bool isApplying) {
    return value != null && !isApplying;
  }

  bool _alwaysOnUsbWritable(BatteryDevicesState state) {
    return state.alwaysOnUsbChargingEnabled != null &&
        state.alwaysOnUsbWriteSupported &&
        !state.isApplying;
  }

  String _alwaysOnUsbSubtitle(BatteryDevicesState state) {
    if (state.alwaysOnUsbChargingEnabled == null) {
      return 'Unavailable on this device';
    }

    final status = boolEnabledLabel(state.alwaysOnUsbChargingEnabled);
    if (!state.alwaysOnUsbWriteSupported) {
      return '$status (read-only until backend write support is available)';
    }

    return '$status (writes require admin approval)';
  }
}
